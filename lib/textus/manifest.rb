require "yaml"

module Textus
  class Manifest
    # New stricter grammar: lowercase + digits + internal hyphens. No underscores.
    KEY_SEGMENT = /\A[a-z0-9][a-z0-9-]*\z/
    MAX_SEGMENTS = 8
    MAX_SEGMENT_LEN = 64

    EXT_TO_FORMAT = {
      ".md" => "markdown",
      ".json" => "json",
      ".yaml" => "yaml",
      ".yml" => "yaml",
      ".txt" => "text",
    }.freeze

    attr_reader :root, :entries, :raw

    def zones
      @zones ||= Array(@raw["zones"]).to_h { |z| [z["name"], Array(z["writable_by"])] }
    end

    def zone_writers(zone_name)
      zones[zone_name] or raise UsageError.new("undeclared zone '#{zone_name}'")
    end

    def self.load(root)
      manifest_path = File.join(root, "manifest.yaml")
      raise IoError.new("manifest not found: #{manifest_path}") unless File.exist?(manifest_path)

      raw = YAML.safe_load_file(manifest_path, aliases: false)
      unless raw["version"] == PROTOCOL
        msg = if raw["version"] == "textus/1"
                "manifest is textus/1; run 'textus migrate v2' to upgrade. See SPEC §15."
              else
                "unsupported manifest version #{raw["version"].inspect}"
              end
        raise BadFrontmatter.new(manifest_path, msg)
      end

      new(root, raw)
    end

    def initialize(root, raw)
      @root = root
      @raw = raw
      raise BadFrontmatter.new(File.join(root, "manifest.yaml"), "manifest must declare zones:") if Array(raw["zones"]).empty?

      @entries = Array(raw["entries"]).map { |e| ManifestEntry.new(self, e) }
      validate_declared_keys!
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
      raise UnknownKey.new(key, suggestions: suggestions_for(key)) if candidates.empty?

      entry, esegs = candidates.first
      remaining = segments[esegs.length..]
      if remaining.empty?
        path = resolve_leaf_path(entry)
        [entry, path, []]
      else
        raise UnknownKey.new(key, suggestions: suggestions_for(key)) unless entry.nested

        primary_ext = Entry.for_format(entry.format).extensions.first
        path = File.join(@root, "zones", entry.path, *remaining) + primary_ext
        [entry, path, remaining]
      end
    end

    # Returns up to 5 dotted keys from the manifest that look similar to the
    # requested key, ranked by shared-prefix length then Levenshtein distance.
    def suggestions_for(key)
      candidates = enumerate.map { |r| r[:key] }
      # Include declared (non-nested) entry keys even if file is missing.
      candidates.concat(@entries.reject(&:nested).map(&:key))
      candidates.uniq!
      KeyDistance.suggest(key, candidates, limit: 5)
    rescue StandardError
      []
    end

    # Enumerate all entry files reachable through the manifest. Returns
    # [{ key:, path:, manifest_entry: }, ...]
    # rubocop:disable Metrics/AbcSize
    def enumerate(prefix: nil)
      out = []
      @entries.each do |entry|
        if entry.nested
          base = File.join(@root, "zones", entry.path)
          next unless File.directory?(base)

          glob_pattern = nested_glob(entry.format)
          Dir.glob(File.join(base, glob_pattern)).each do |fp|
            rel = fp.sub(%r{\A#{Regexp.escape(base)}/?}, "")
            stripped = rel.sub(/#{Regexp.escape(File.extname(rel))}\z/, "")
            segs = stripped.split("/").reject(&:empty?)
            next if segs.empty?

            illegal = segs.find { |s| !valid_segment?(s) }
            if illegal
              warn("textus: skipping illegal key segment '#{illegal}' at #{fp} — run 'textus migrate-keys --dry-run'")
              next
            end

            full_key = (entry.key.split(".") + segs).join(".")
            out << { key: full_key, path: fp, manifest_entry: entry }
          end
        else
          fp = resolve_leaf_path(entry)
          out << { key: entry.key, path: fp, manifest_entry: entry } if File.exist?(fp)
        end
      end
      out.select! { |row| row[:key] == prefix || row[:key].start_with?("#{prefix}.") } if prefix
      out.sort_by { |row| row[:key] }
    end
    # rubocop:enable Metrics/AbcSize

    # Validates all declared entry keys; raises UsageError listing all offenders.
    def validate_keys!
      offenders = []
      @entries.each do |entry|
        validate_key!(entry.key)
      rescue UsageError => e
        offenders << e.message
      end
      raise UsageError.new("invalid manifest keys: #{offenders.join("; ")}") unless offenders.empty?
    end

    def validate_key!(key)
      raise UsageError.new("empty key") if key.nil? || key.empty?

      segs = key.split(".")
      raise UsageError.new("key '#{key}' has #{segs.length} segments (max #{MAX_SEGMENTS})") if segs.length > MAX_SEGMENTS

      segs.each do |seg|
        if seg.empty?
          raise UsageError.new("empty segment in key '#{key}'")
        elsif seg.length > MAX_SEGMENT_LEN
          raise UsageError.new("segment '#{seg}' in key '#{key}' exceeds #{MAX_SEGMENT_LEN} chars")
        elsif !seg.match?(KEY_SEGMENT)
          raise UsageError.new(
            "invalid key segment '#{seg}' in '#{key}': must match [a-z0-9][a-z0-9-]* " \
            "(lowercase, digits, hyphens; no underscores or uppercase)",
          )
        end
      end
    end

    private

    def valid_segment?(seg)
      return false if seg.nil? || seg.empty?
      return false if seg.length > MAX_SEGMENT_LEN

      seg.match?(KEY_SEGMENT)
    end

    def validate_declared_keys!
      @entries.each { |e| validate_key!(e.key) }
    end

    def resolve_leaf_path(entry)
      Textus::Path.resolve(self, entry)
    end

    def nested_glob(format)
      case format
      when "markdown" then "**/*.md"
      when "json" then "**/*.json"
      when "yaml" then "**/*.{yaml,yml}"
      when "text" then "**/*.txt"
      else raise UsageError.new("unknown format #{format.inspect} for nested glob")
      end
    end
  end
end
