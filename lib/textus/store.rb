require "fileutils"
require "time"

module Textus
  class Store
    attr_reader :root, :manifest

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
      @schemas = {}
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
      mentry, path, _ = @manifest.resolve(key)
      raise UnknownKey, key unless File.exist?(path)
      raw = File.binread(path)
      parsed = Entry.parse(raw, path: path)
      fm = parsed["frontmatter"]
      enforce_name_match!(path, fm)
      schema = schema_for(mentry.schema)
      if schema
        schema.validate!(fm)
      end
      build_envelope(key, mentry, path, fm, parsed["body"], Etag.for_bytes(raw))
    end

    def where(key)
      mentry, path, _ = @manifest.resolve(key)
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
      mentry, _, _ = @manifest.resolve(key)
      schema = schema_for(mentry.schema)
      {
        "protocol" => PROTOCOL,
        "key" => key,
        "schema_ref" => mentry.schema,
        "schema" => schema&.to_h,
      }
    end

    def put(key, frontmatter:, body:, if_etag: nil, as: Role::DEFAULT)
      mentry, path, _ = @manifest.resolve(key)
      writers = @manifest.zone_writers(mentry.zone)
      unless writers.include?(as)
        raise WriteForbidden.new(key, mentry.zone)
      end

      basename = File.basename(path, ".md")
      if frontmatter["name"] && frontmatter["name"] != basename
        raise BadFrontmatter.new(path, "frontmatter name '#{frontmatter["name"]}' does not match basename '#{basename}'")
      end

      schema = schema_for(mentry.schema)
      schema.validate!(frontmatter) if schema

      etag_before = File.exist?(path) ? Etag.for_file(path) : nil
      if if_etag
        raise EtagMismatch.new(key, if_etag, etag_before) if etag_before != if_etag
      end

      FileUtils.mkdir_p(File.dirname(path))
      bytes = Entry.serialize(frontmatter: frontmatter, body: body)
      File.binwrite(path, bytes)
      etag_after = Etag.for_bytes(bytes)
      audit_log.append(role: as, verb: "put", key: key, etag_before: etag_before, etag_after: etag_after)
      build_envelope(key, mentry, path, frontmatter, body, etag_after)
    end

    def delete(key, if_etag: nil, as: Role::DEFAULT)
      mentry, path, _ = @manifest.resolve(key)
      writers = @manifest.zone_writers(mentry.zone)
      raise WriteForbidden.new(key, mentry.zone) unless writers.include?(as)
      raise UnknownKey, key unless File.exist?(path)
      etag_before = Etag.for_file(path)
      raise EtagMismatch.new(key, if_etag, etag_before) if if_etag && if_etag != etag_before
      File.delete(path)
      audit_log.append(role: as, verb: "delete", key: key, etag_before: etag_before, etag_after: nil)
      { "protocol" => PROTOCOL, "ok" => true, "key" => key, "deleted" => true }
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
      { "protocol" => PROTOCOL, "ok" => violations.empty?, "violations" => violations }
    end

    def stale(prefix: nil, zone: nil)
      out = []
      @manifest.entries.each do |mentry|
        next unless mentry.zone == "derived"
        next if zone && mentry.zone != zone
        gen = mentry.generator
        next unless gen
        next if prefix && !(mentry.key == prefix || mentry.key.start_with?("#{prefix}."))

        path = mentry.path.end_with?(".md") ? File.join(@root, "zones", mentry.path) : File.join(@root, "zones", mentry.path + ".md")

        if !File.exist?(path)
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
        gen_time = Time.parse(generated_at.to_s) rescue nil
        unless gen_time
          out << stale_row(mentry, path, "unparseable generated.at: #{generated_at.inspect}")
          next
        end

        offender = newest_source_after(gen, gen_time)
        out << stale_row(mentry, path, "source '#{offender}' modified after generated.at") if offender
      end
      out
    end

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
      if fm["name"] && fm["name"] != basename
        raise BadFrontmatter.new(path, "frontmatter name '#{fm["name"]}' does not match basename '#{basename}'")
      end
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
