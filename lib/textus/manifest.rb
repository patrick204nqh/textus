require "yaml"

module Textus
  class Manifest
    KEY_SEGMENT = /\A[a-z0-9](?:[a-z0-9_-]*[a-z0-9])?\z/

    attr_reader :root, :entries, :raw

    def self.load(root)
      manifest_path = File.join(root, "manifest.yaml")
      raise IoError.new("manifest not found: #{manifest_path}") unless File.exist?(manifest_path)
      raw = YAML.safe_load(File.read(manifest_path), aliases: false)
      raise BadFrontmatter.new(manifest_path, "unsupported manifest version #{raw["version"].inspect}") unless raw["version"] == PROTOCOL
      new(root, raw)
    end

    def initialize(root, raw)
      @root = root
      @raw = raw
      @entries = Array(raw["entries"]).map { |e| ManifestEntry.new(self, e) }
    end

    # Returns [ManifestEntry, resolved_path, remaining_segments]
    def resolve(key)
      validate_key!(key)
      segments = key.split(".")
      # longest-prefix match
      candidates = @entries
        .map { |e| [e, e.key.split(".")] }
        .select { |(_, esegs)| esegs == segments[0, esegs.length] }
        .sort_by { |(_, esegs)| -esegs.length }
      raise UnknownKey, key if candidates.empty?
      entry, esegs = candidates.first
      remaining = segments[esegs.length..]
      if remaining.empty?
        path = if entry.path.end_with?(".md")
                 File.join(@root, entry.path)
               else
                 File.join(@root, entry.path + ".md")
               end
        [entry, path, []]
      else
        raise UnknownKey, key unless entry.nested
        path = File.join(@root, entry.path, *remaining) + ".md"
        [entry, path, remaining]
      end
    end

    # Enumerate all entry files reachable through the manifest. Returns
    # [{ key:, path:, manifest_entry: }, ...]
    def enumerate(prefix: nil)
      out = []
      @entries.each do |entry|
        if entry.nested
          base = File.join(@root, entry.path)
          next unless File.directory?(base)
          Dir.glob(File.join(base, "**", "*.md")).each do |fp|
            rel = fp.sub(/\A#{Regexp.escape(base)}\/?/, "").sub(/\.md\z/, "")
            segs = rel.split("/").reject(&:empty?)
            next if segs.empty?
            full_key = (entry.key.split(".") + segs).join(".")
            out << { key: full_key, path: fp, manifest_entry: entry }
          end
        else
          if entry.path.end_with?(".md")
            fp = File.join(@root, entry.path)
            out << { key: entry.key, path: fp, manifest_entry: entry } if File.exist?(fp)
          else
            fp = File.join(@root, entry.path + ".md")
            out << { key: entry.key, path: fp, manifest_entry: entry } if File.exist?(fp)
          end
        end
      end
      out.select! { |row| row[:key] == prefix || row[:key].start_with?("#{prefix}.") } if prefix
      out.sort_by { |row| row[:key] }
    end

    def validate_key!(key)
      raise UsageError.new("empty key") if key.nil? || key.empty?
      key.split(".").each do |seg|
        unless seg.match?(KEY_SEGMENT)
          raise UsageError.new("invalid key segment '#{seg}' in '#{key}'")
        end
      end
    end
  end

  class ManifestEntry
    attr_reader :key, :path, :zone, :schema, :owner, :nested, :generator, :raw
    def initialize(manifest, raw)
      @raw = raw
      @key = raw["key"] or raise UsageError.new("manifest entry missing key")
      @path = raw["path"] or raise UsageError.new("manifest entry '#{@key}' missing path")
      @zone = raw["zone"] or raise UsageError.new("manifest entry '#{@key}' missing zone")
      @schema = raw["schema"]
      @owner = raw["owner"]
      @nested = raw["nested"] == true
      @generator = raw["generator"]
    end

    def agent_writable?
      @zone == "state"
    end
  end
end
