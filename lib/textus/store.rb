require "fileutils"
require "time"
require "timeout"

module Textus
  class Store
    HOOK_TIMEOUT_SECONDS = 2

    attr_reader :root, :manifest, :registry

    def self.discover(start_dir = Dir.pwd)
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

    def initialize(root)
      @root = File.expand_path(root)
      @manifest = Manifest.load(@root)
      @registry = ExtensionRegistry.new
      @schemas = {}
      load_extensions
    end

    def load_extensions
      Textus.with_registry(@registry) do
        BuiltinFetchers.register_all
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
      raise UnknownKey.new(key) unless File.exist?(path)

      raw = File.binread(path)
      parsed = Entry.parse(raw, path: path)
      fm = parsed["frontmatter"]
      enforce_name_match!(path, fm)
      schema = schema_for(mentry.schema)
      schema&.validate!(fm)
      build_envelope(key, mentry, path, fm, parsed["body"], Etag.for_bytes(raw))
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

    def put(key, frontmatter:, body:, if_etag: nil, as: Role::DEFAULT)
      mentry, path, = @manifest.resolve(key)
      writers = @manifest.zone_writers(mentry.zone)
      raise WriteForbidden.new(key, mentry.zone) unless writers.include?(as)

      basename = File.basename(path, ".md")
      if frontmatter["name"] && frontmatter["name"] != basename
        raise BadFrontmatter.new(path, "frontmatter name '#{frontmatter["name"]}' does not match basename '#{basename}'")
      end

      schema = schema_for(mentry.schema)
      schema&.validate!(frontmatter)

      etag_before = File.exist?(path) ? Etag.for_file(path) : nil
      raise EtagMismatch.new(key, if_etag, etag_before) if if_etag && (etag_before != if_etag)

      FileUtils.mkdir_p(File.dirname(path))
      bytes = Entry.serialize(frontmatter: frontmatter, body: body)
      File.binwrite(path, bytes)
      etag_after = Etag.for_bytes(bytes)
      audit_log.append(role: as, verb: "put", key: key, etag_before: etag_before, etag_after: etag_after)
      envelope = build_envelope(key, mentry, path, frontmatter, body, etag_after)
      fire_event(:put, key: key, envelope: envelope)
      envelope
    end

    def delete(key, if_etag: nil, as: Role::DEFAULT)
      mentry, path, = @manifest.resolve(key)
      writers = @manifest.zone_writers(mentry.zone)
      raise WriteForbidden.new(key, mentry.zone) unless writers.include?(as)
      raise UnknownKey.new(key) unless File.exist?(path)

      etag_before = Etag.for_file(path)
      raise EtagMismatch.new(key, if_etag, etag_before) if if_etag && if_etag != etag_before

      File.delete(path)
      audit_log.append(role: as, verb: "delete", key: key, etag_before: etag_before, etag_after: nil)
      fire_event(:delete, key: key)
      { "protocol" => PROTOCOL, "ok" => true, "key" => key, "deleted" => true }
    end

    def fire_event(event, **kwargs)
      view = StoreView.new(self)
      @registry.hooks(event).each do |entry|
        Timeout.timeout(HOOK_TIMEOUT_SECONDS) { entry[:callable].call(store: view, **kwargs) }
      rescue StandardError => _e
        # Will be properly audited in Task 12 once AuditLog supports extras:.
        # For now: hook errors are silently swallowed (write/delete already committed).
        # Timeout::Error inherits from StandardError, so it's covered here.
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

        env["frontmatter"].each_key do |field|
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

        path = mentry.path.end_with?(".md") ? File.join(@root, "zones", mentry.path) : File.join(@root, "zones", mentry.path + ".md")

        unless File.exist?(path)
          out << stale_row(mentry, path, "derived entry has never been generated")
          next
        end

        raw = File.binread(path)
        parsed = Entry.parse(raw, path: path)
        generated_at = parsed["frontmatter"].dig("generated", "at")
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
        next unless mentry.fetcher
        next if zone && mentry.zone != zone
        next if prefix && !(mentry.key == prefix || mentry.key.start_with?("#{prefix}."))

        ttl = parse_ttl(mentry.ttl)
        next unless ttl

        path = mentry.path.end_with?(".md") ? File.join(@root, "zones", mentry.path) : File.join(@root, "zones", mentry.path + ".md")

        unless File.exist?(path)
          out << intake_stale_row(mentry, path, "never refreshed")
          next
        end

        fm = Entry.parse(File.binread(path), path: path)["frontmatter"]
        last_str = fm["last_refreshed_at"]
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

    private

    def audit_log
      @audit_log ||= AuditLog.new(@root)
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
      { "key" => mentry.key, "path" => path, "fetcher" => mentry.fetcher, "reason" => reason }
    end

    def stale_row(mentry, path, reason)
      {
        "key" => mentry.key,
        "path" => path,
        "generator" => mentry.generator,
        "reason" => reason,
      }
    end

    def enforce_name_match!(path, fm)
      basename = File.basename(path, ".md")
      return unless fm["name"] && fm["name"] != basename

      raise BadFrontmatter.new(path, "frontmatter name '#{fm["name"]}' does not match basename '#{basename}'")
    end

    def build_envelope(key, mentry, path, fm, body, etag)
      {
        "protocol" => PROTOCOL,
        "key" => key,
        "zone" => mentry.zone,
        "owner" => mentry.owner,
        "path" => path,
        "frontmatter" => fm,
        "body" => body,
        "etag" => etag,
        "schema_ref" => mentry.schema,
      }
    end
  end
end
