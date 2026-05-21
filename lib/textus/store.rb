require "fileutils"
require "securerandom"
require "time"
require "timeout"

module Textus
  # rubocop:disable Metrics/ClassLength
  class Store
    HOOK_TIMEOUT_SECONDS = 2

    attr_reader :root, :manifest, :registry

    # A Textus UID: 16 lowercase hex chars (SecureRandom.hex(8)). Not a UUID —
    # short on purpose. Random enough for collision-never-in-practice within a
    # single store.
    def self.mint_uid
      SecureRandom.hex(8)
    end

    def self.discover(start_dir = Dir.pwd, root: nil)
      explicit = root || ENV.fetch("TEXTUS_ROOT", nil)
      return discover_explicit(explicit) if explicit

      dir = File.expand_path(start_dir)
      loop do
        candidate = File.join(dir, ".textus")
        return new(candidate) if File.directory?(candidate) && File.exist?(File.join(candidate, "manifest.yaml"))

        parent = File.dirname(dir)
        break if parent == dir

        dir = parent
      end
      raise IoError.new("no .textus directory found from #{start_dir}")
    end

    private_class_method def self.discover_explicit(root_arg)
      abs = File.expand_path(root_arg)
      raise IoError.new("no textus store at #{abs}") unless File.directory?(abs) && File.exist?(File.join(abs, "manifest.yaml"))

      new(abs)
    end

    def initialize(root)
      @root = File.expand_path(root)
      @manifest = Manifest.load(@root)
      @registry = ExtensionRegistry.new
      @schemas = {}
      load_extensions
    end

    def load_extensions
      Textus.with_registry(@registry) do
        BuiltinActions.register_all
        dir = File.join(@root, "extensions")
        return unless File.directory?(dir)

        Dir.glob(File.join(dir, "*.rb")).sort.each do |f| # rubocop:disable Lint/RedundantDirGlobSort
          begin
            load(f)
          rescue StandardError, ScriptError => e
            raise UsageError.new("failed loading extension #{File.basename(f)}: #{e.class}: #{e.message}")
          end
        end
      end
    end

    def schema_for(name)
      return nil if name.nil?

      @schemas[name] ||= begin
        sp = File.join(@root, "schemas", "#{name}.yaml")
        raise IoError.new("schema not found: #{sp}") unless File.exist?(sp)

        Schema.load(sp)
      end
    end

    def get(key)
      mentry, path, = @manifest.resolve(key)
      raise UnknownKey.new(key, suggestions: @manifest.suggestions_for(key)) unless File.exist?(path)

      raw = File.binread(path)
      parsed = Entry.for_format(mentry.format).parse(raw, path: path)
      meta = parsed["_meta"]
      content = parsed["content"]
      enforce_name_match!(path, meta, mentry.format)
      schema = schema_for(mentry.schema)
      if schema
        case mentry.format
        when "markdown" then schema.validate!(meta)
        when "json", "yaml" then schema.validate!(content || {})
          # text: schema forbidden by manifest validation
        end
      end
      build_envelope(key, mentry, path, meta, parsed["body"], Etag.for_bytes(raw), content: content)
    end

    def where(key)
      mentry, path, = @manifest.resolve(key)
      {
        "protocol" => PROTOCOL,
        "key" => key,
        "zone" => mentry.zone,
        "owner" => mentry.owner,
        "path" => path,
      }
    end

    def list(prefix: nil, zone: nil)
      rows = @manifest.enumerate(prefix: prefix)
      rows = rows.select { |r| r[:manifest_entry].zone == zone } if zone
      rows.map do |row|
        {
          "key" => row[:key],
          "zone" => row[:manifest_entry].zone,
          "path" => row[:path],
        }
      end
    end

    def schema_envelope(key)
      mentry, = @manifest.resolve(key)
      schema = schema_for(mentry.schema)
      {
        "protocol" => PROTOCOL,
        "key" => key,
        "schema_ref" => mentry.schema,
        "schema" => schema&.to_h,
      }
    end

    # rubocop:disable Metrics/ParameterLists
    def put(key, meta: nil, body: nil, content: nil, if_etag: nil, as: Role::DEFAULT, suppress_events: false)
      # rubocop:enable Metrics/ParameterLists
      @manifest.validate_key!(key)
      mentry, path, = @manifest.resolve(key)
      writers = @manifest.zone_writers(mentry.zone)
      raise WriteForbidden.new(key, mentry.zone, writers: writers) unless writers.include?(as)

      meta ||= {}
      strategy = Entry.for_format(mentry.format)

      existing_uid = existing_uid_for(mentry, path)
      meta, content = ensure_uid(mentry.format, meta, content, existing_uid)

      bytes, eff_meta, eff_body, eff_content = serialize_for_put(
        mentry: mentry, path: path, strategy: strategy,
        meta: meta, body: body, content: content
      )

      enforce_name_match!(path, eff_meta, mentry.format)

      schema = schema_for(mentry.schema)
      if schema
        case mentry.format
        when "markdown" then schema.validate!(eff_meta)
        when "json", "yaml" then schema.validate!(eff_content || {})
        end
      end

      etag_before = File.exist?(path) ? Etag.for_file(path) : nil
      raise EtagMismatch.new(key, if_etag, etag_before) if if_etag && (etag_before != if_etag)

      FileUtils.mkdir_p(File.dirname(path))
      File.binwrite(path, bytes)
      etag_after = Etag.for_bytes(bytes)
      audit_log.append(role: as, verb: "put", key: key, etag_before: etag_before, etag_after: etag_after)
      envelope = build_envelope(key, mentry, path, eff_meta, eff_body, etag_after, content: eff_content)
      fire_event(:put, key: key, envelope: envelope) unless suppress_events
      envelope
    end

    def delete(key, if_etag: nil, as: Role::DEFAULT, suppress_events: false)
      mentry, path, = @manifest.resolve(key)
      writers = @manifest.zone_writers(mentry.zone)
      raise WriteForbidden.new(key, mentry.zone, writers: writers) unless writers.include?(as)
      raise UnknownKey.new(key, suggestions: @manifest.suggestions_for(key)) unless File.exist?(path)

      etag_before = Etag.for_file(path)
      raise EtagMismatch.new(key, if_etag, etag_before) if if_etag && if_etag != etag_before

      File.delete(path)
      audit_log.append(role: as, verb: "delete", key: key, etag_before: etag_before, etag_after: nil)
      fire_event(:delete, key: key) unless suppress_events
      { "protocol" => PROTOCOL, "ok" => true, "key" => key, "deleted" => true }
    end

    def fire_event(event, **kwargs)
      view = StoreView.new(self)
      @registry.hooks(event).each do |entry|
        name = entry[:name]
        Timeout.timeout(HOOK_TIMEOUT_SECONDS) { entry[:callable].call(store: view, **kwargs) }
      rescue StandardError => e
        extras = { "event" => event.to_s, "hook" => name.to_s, "error" => "#{e.class}: #{e.message}" }
        extras["target_key"]  = kwargs[:target_key]  if kwargs.key?(:target_key)
        extras["pending_key"] = kwargs[:pending_key] if kwargs.key?(:pending_key)
        audit_log.append(
          role: "script", verb: "event_error",
          key: kwargs[:key] || kwargs[:target_key] || kwargs[:pending_key] || "-",
          etag_before: nil, etag_after: nil,
          extras: extras
        )
      end
    end

    def accept(key, as:)
      Proposal.accept(self, key, as: as)
    end

    def deps(key)      = Dependencies.deps_of(@manifest, key)
    def rdeps(key)     = Dependencies.rdeps_of(@manifest, key)
    def published      = Dependencies.published_of(@manifest)

    def validate_all
      violations = []
      @manifest.enumerate.each do |row|
        begin
          get(row[:key])
        rescue Textus::Error => e
          violations << { "key" => row[:key], "code" => e.code, "message" => e.message }
        end
      end

      @manifest.enumerate.each do |row|
        mentry = row[:manifest_entry]
        next unless mentry.schema

        schema = schema_for(mentry.schema)
        next unless schema

        env = begin
          get(row[:key])
        rescue StandardError
          next
        end
        last_writer = audit_log.last_writer_for(row[:key])
        next if last_writer.nil?

        env["_meta"].each_key do |field|
          owner = schema.maintained_by(field)
          next if owner.nil?
          next if last_writer == owner
          next if last_writer == "human"

          violations << {
            "key" => row[:key],
            "code" => "role_authority",
            "field" => field,
            "expected" => owner,
            "last_writer" => last_writer,
          }
        end
      end

      { "protocol" => PROTOCOL, "ok" => violations.empty?, "violations" => violations }
    end

    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity, Metrics/BlockLength
    def stale(prefix: nil, zone: nil)
      out = []
      @manifest.entries.each do |mentry|
        next unless mentry.zone == "derived"
        next if zone && mentry.zone != zone

        gen = mentry.generator
        next unless gen
        next if prefix && !(mentry.key == prefix || mentry.key.start_with?("#{prefix}."))

        path = path_for_entry(mentry)

        unless File.exist?(path)
          out << stale_row(mentry, path, "derived entry has never been generated")
          next
        end

        raw = File.binread(path)
        parsed = Entry.for_format(mentry.format).parse(raw, path: path)
        generated_at = parsed["_meta"].dig("generated", "at")
        unless generated_at
          out << stale_row(mentry, path, "missing generated.at frontmatter")
          next
        end
        gen_time = begin
          Time.parse(generated_at.to_s)
        rescue StandardError
          nil
        end
        unless gen_time
          out << stale_row(mentry, path, "unparseable generated.at: #{generated_at.inspect}")
          next
        end

        offender = newest_source_after(gen, gen_time)
        out << stale_row(mentry, path, "source '#{offender}' modified after generated.at") if offender
      end

      @manifest.entries.each do |mentry|
        next unless mentry.action
        next if zone && mentry.zone != zone
        next if prefix && !(mentry.key == prefix || mentry.key.start_with?("#{prefix}."))

        ttl = parse_ttl(mentry.ttl)
        next unless ttl

        path = path_for_entry(mentry)

        unless File.exist?(path)
          out << intake_stale_row(mentry, path, "never refreshed")
          next
        end

        meta = Entry.for_format(mentry.format).parse(File.binread(path), path: path)["_meta"]
        last_str = meta["last_refreshed_at"]
        if last_str.nil?
          out << intake_stale_row(mentry, path, "never refreshed (no last_refreshed_at)")
          next
        end

        last = begin
          Time.parse(last_str.to_s)
        rescue StandardError
          nil
        end
        out << intake_stale_row(mentry, path, "ttl exceeded (#{ttl}s)") if last.nil? || (Time.now - last) > ttl
      end

      out
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity, Metrics/BlockLength

    # Returns the Textus UID for a key (or nil if the entry has none yet).
    # Raises UnknownKey if the key doesn't resolve to a real file.
    def uid(key)
      env = get(key)
      env["uid"]
    end

    # Move an entry from old_key to new_key within the same zone. Preserves
    # uid (minting one first if absent), validates both keys against the
    # manifest, refuses to clobber, and writes one mv audit row.
    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    def mv(old_key, new_key, as: Role::DEFAULT, dry_run: false)
      @manifest.validate_key!(old_key)
      @manifest.validate_key!(new_key)
      raise UsageError.new("mv: old and new keys are identical") if old_key == new_key

      old_mentry, old_path, = @manifest.resolve(old_key)
      raise UnknownKey.new(old_key) unless File.exist?(old_path)

      new_mentry, new_path, = @manifest.resolve(new_key)

      if old_mentry.zone != new_mentry.zone
        raise UsageError.new(
          "mv: cross-zone move refused (#{old_mentry.zone} → #{new_mentry.zone}). " \
          "Use put+delete for cross-zone moves.",
        )
      end
      if old_mentry.format != new_mentry.format
        raise UsageError.new(
          "mv: format mismatch (#{old_mentry.format} → #{new_mentry.format}); refusing.",
        )
      end

      writers = @manifest.zone_writers(old_mentry.zone)
      raise WriteForbidden.new(old_key, old_mentry.zone, writers: writers) unless writers.include?(as)

      raise UsageError.new("mv: target '#{new_key}' already exists at #{new_path}") if File.exist?(new_path)

      # Mint uid before the move so the audit row carries it.
      pre_env = get(old_key)
      current_uid = pre_env["uid"]
      etag_before = pre_env["etag"]

      if dry_run
        return {
          "protocol" => PROTOCOL, "ok" => true, "dry_run" => true,
          "from_key" => old_key, "to_key" => new_key,
          "from_path" => old_path, "to_path" => new_path,
          "uid" => current_uid
        }
      end

      if current_uid.nil?
        # Write the uid in place first so the source file carries it before mv.
        pre_env = put(old_key,
                      meta: pre_env["_meta"],
                      body: pre_env["body"],
                      content: pre_env["content"],
                      as: as,
                      suppress_events: true)
        current_uid = pre_env["uid"]
        etag_before = pre_env["etag"]
      end

      FileUtils.mkdir_p(File.dirname(new_path))
      FileUtils.mv(old_path, new_path)
      rewrite_name_for_mv!(new_mentry, new_path, new_key)
      etag_after = Etag.for_file(new_path)

      audit_log.append(
        role: as, verb: "mv", key: new_key,
        etag_before: etag_before, etag_after: etag_after,
        extras: {
          "from_key" => old_key, "to_key" => new_key,
          "from_path" => old_path, "to_path" => new_path,
          "uid" => current_uid
        }
      )

      env = get(new_key)
      {
        "protocol" => PROTOCOL, "ok" => true,
        "from_key" => old_key, "to_key" => new_key,
        "from_path" => old_path, "to_path" => new_path,
        "uid" => current_uid,
        "envelope" => env
      }
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    private

    # If the moved file carries a `name:` field (markdown) or `_meta.name`
    # (json/yaml), rewrite it to the new basename so enforce_name_match! stays
    # happy on the next read. Only touches the bytes when name actually changes.
    def rewrite_name_for_mv!(mentry, new_path, new_key)
      strategy = Entry.for_format(mentry.format)
      raw = File.binread(new_path)
      parsed = strategy.parse(raw, path: new_path)
      basename = new_key.split(".").last

      case mentry.format
      when "markdown"
        meta = parsed["_meta"] || {}
        return unless meta.is_a?(Hash) && meta["name"].is_a?(String) && meta["name"] != basename

        meta = meta.merge("name" => basename)
        File.binwrite(new_path, strategy.serialize(meta: meta, body: parsed["body"]))
      when "json", "yaml"
        meta = parsed["_meta"]
        return unless meta.is_a?(Hash) && meta["name"].is_a?(String) && meta["name"] != basename

        new_meta = meta.merge("name" => basename)
        File.binwrite(new_path, strategy.serialize(meta: new_meta, body: "", content: parsed["content"]))
      end
    end

    def existing_uid_for(mentry, path)
      return nil unless File.exist?(path)

      raw = File.binread(path)
      parsed = Entry.for_format(mentry.format).parse(raw, path: path)
      extract_uid(parsed["_meta"])
    rescue StandardError
      nil
    end

    # Ensures the payload carries a uid: preserve existing, else mint.
    # Returns [meta, content] possibly mutated.
    def ensure_uid(format, meta, content, existing_uid)
      case format
      when "markdown", "json", "yaml"
        m = meta.is_a?(Hash) ? meta.dup : {}
        m["uid"] = existing_uid || Store.mint_uid unless m["uid"].is_a?(String) && !m["uid"].empty?
        [m, content]
      else
        # text: no uid channel
        [meta, content]
      end
    end

    def audit_log
      @audit_log ||= AuditLog.new(@root)
    end

    def path_for_entry(mentry)
      primary_ext = Entry.for_format(mentry.format).extensions.first
      if File.extname(mentry.path) == ""
        File.join(@root, "zones", mentry.path + primary_ext)
      else
        File.join(@root, "zones", mentry.path)
      end
    end

    def newest_source_after(gen, gen_time)
      Array(gen["sources"]).each do |src|
        if src.match?(/\A[a-z0-9.][a-z0-9._-]*\z/) && !src.include?("/")
          @manifest.enumerate(prefix: src).each do |row|
            return src if File.mtime(row[:path]) > gen_time
          end
        else
          abs = File.absolute_path?(src) ? src : File.join(File.dirname(@root), src)
          if File.directory?(abs)
            Dir.glob(File.join(abs, "**", "*")).each do |fp|
              next unless File.file?(fp)
              return src if File.mtime(fp) > gen_time
            end
          elsif File.exist?(abs)
            return src if File.mtime(abs) > gen_time
          end
        end
      end
      nil
    end

    def parse_ttl(s)
      return nil unless s

      m = s.to_s.match(/\A(\d+)([smhd])\z/) or return nil
      n = m[1].to_i
      case m[2]
      when "s" then n
      when "m" then n * 60
      when "h" then n * 3600
      when "d" then n * 86_400
      end
    end

    def intake_stale_row(mentry, path, reason)
      { "key" => mentry.key, "path" => path, "action" => mentry.action, "reason" => reason }
    end

    def stale_row(mentry, path, reason)
      {
        "key" => mentry.key,
        "path" => path,
        "generator" => mentry.generator,
        "reason" => reason,
      }
    end

    def enforce_name_match!(path, meta, format)
      return unless %w[markdown json yaml].include?(format)
      return unless meta.is_a?(Hash) && meta["name"]

      ext = Entry.for_format(format).extensions.first
      basename = File.basename(path, ext)
      return if meta["name"] == basename

      raise BadFrontmatter.new(path, "name '#{meta["name"]}' does not match basename '#{basename}'")
    end

    def serialize_for_put(mentry:, path:, strategy:, meta:, body:, content:)
      case mentry.format
      when "markdown", "text"
        bytes = strategy.serialize(meta: meta, body: body.to_s)
        [bytes, meta, body.to_s, nil]
      when "json", "yaml"
        raise UsageError.new("put for #{mentry.format} requires content: or body:") if content.nil? && (body.nil? || body.to_s.empty?)

        if content.nil?
          # Caller passed raw body; validate by parsing.
          begin
            parsed = strategy.parse(body.to_s, path: path)
          rescue BadFrontmatter => e
            raise BadContent.new(path, "bad_content: #{e.message}")
          end
          eff_meta = parsed["_meta"]
          eff_content = parsed["content"]
          [body.to_s, eff_meta, body.to_s, eff_content]
        else
          bytes = strategy.serialize(meta: meta, body: "", content: content)
          [bytes, meta, bytes, content]
        end
      else
        raise UsageError.new("unknown format #{mentry.format.inspect}")
      end
    end

    # rubocop:disable Metrics/ParameterLists
    def build_envelope(key, mentry, path, meta, body, etag, content: nil)
      # rubocop:enable Metrics/ParameterLists
      env = {
        "protocol" => PROTOCOL,
        "key" => key,
        "zone" => mentry.zone,
        "owner" => mentry.owner,
        "path" => path,
        "format" => mentry.format,
        "_meta" => meta,
        "body" => body,
        "etag" => etag,
        "schema_ref" => mentry.schema,
        "uid" => extract_uid(meta),
      }
      env["content"] = content unless content.nil?
      env
    end

    # Pull a Textus UID out of the unified _meta hash.
    def extract_uid(meta)
      v = meta.is_a?(Hash) ? meta["uid"] : nil
      v.is_a?(String) ? v : nil
    end
  end
  # rubocop:enable Metrics/ClassLength
end
