require "fileutils"
require "securerandom"

module Textus
  class Store
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

    def fire_event(event, **)
      Events.new(self).call(event, **)
    end

    def accept(key, as:)
      Proposal.accept(self, key, as: as)
    end

    def deps(key)      = Dependencies.deps_of(@manifest, key)
    def rdeps(key)     = Dependencies.rdeps_of(@manifest, key)
    def published      = Dependencies.published_of(@manifest)

    def validate_all
      Validator.new(self).call
    end

    def stale(prefix: nil, zone: nil)
      Staleness.new(self).call(prefix: prefix, zone: zone)
    end

    # Returns the Textus UID for a key (or nil if the entry has none yet).
    # Raises UnknownKey if the key doesn't resolve to a real file.
    def uid(key)
      env = get(key)
      env["uid"]
    end

    # Move an entry from old_key to new_key within the same zone. Preserves
    # uid (minting one first if absent), validates both keys against the
    # manifest, refuses to clobber, and writes one mv audit row.
    def mv(old_key, new_key, as: Role::DEFAULT, dry_run: false)
      Mover.new(self).call(old_key, new_key, as: as, dry_run: dry_run)
    end

    def audit_log
      @audit_log ||= AuditLog.new(@root)
    end

    private

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
end
