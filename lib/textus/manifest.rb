require "yaml"
require_relative "manifest/schema"
require_relative "manifest/resolution"

module Textus
  class Manifest
    attr_reader :root, :entries, :raw

    def zones
      @zones ||= Array(@raw["zones"]).to_h { |z| [z["name"], Array(z["write_policy"])] }
    end

    def zone_readers
      @zone_readers ||= Array(@raw["zones"]).to_h do |z|
        rp = z["read_policy"]
        [z["name"], rp.nil? ? :all : Array(rp)]
      end
    end

    def zone_writers(zone_name)
      zones[zone_name] or raise UsageError.new("undeclared zone '#{zone_name}'")
    end

    def permission_for(zone_name)
      Textus::Domain::Permission.new(
        zone: zone_name,
        write_policy: zone_writers(zone_name),
        read_policy: zone_readers[zone_name] || :all,
      )
    end

    def self.parse(yaml_text, root: ".")
      raw = YAML.safe_load(yaml_text, aliases: false)
      check_version!(raw, "<string>")
      new(root, raw)
    end

    def self.load(root)
      manifest_path = File.join(root, "manifest.yaml")
      raise IoError.new("manifest not found: #{manifest_path}") unless File.exist?(manifest_path)

      raw = YAML.safe_load_file(manifest_path, aliases: false)
      check_version!(raw, manifest_path)
      new(root, raw)
    end

    def self.check_version!(raw, source)
      return if raw["version"] == PROTOCOL

      raise BadFrontmatter.new(
        source,
        "unsupported manifest version #{raw["version"].inspect}; expected #{PROTOCOL.inspect}",
      )
    end
    private_class_method :check_version!

    def initialize(root, raw)
      @root = root
      @raw = raw
      raise BadFrontmatter.new(File.join(root, "manifest.yaml"), "manifest must declare zones:") if Array(raw["zones"]).empty?

      Schema.validate!(raw)

      @entries = Array(raw["entries"]).map do |e|
        entry = Manifest::Entry::Parser.call(self, e)
        Manifest::Entry::Validators.run_all(entry)
        entry
      end
      validate_declared_keys!
    end

    def rules
      @rules ||= Textus::Manifest::Rules.parse(@raw["rules"] || [])
    end

    def rules_for(key)
      rules.for(key)
    end

    # Returns a Resolution(entry:, path:, remaining:) value object.
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
        Resolution.new(entry: entry, path: path, remaining: [])
      else
        raise UnknownKey.new(key, suggestions: suggestions_for(key)) unless entry.nested

        path = if entry.index_filename
                 File.join(@root, "zones", entry.path, *remaining, entry.index_filename)
               else
                 primary_ext = Textus::Entry.for_format(entry.format).extensions.first
                 File.join(@root, "zones", entry.path, *remaining) + primary_ext
               end
        Resolution.new(entry: entry, path: path, remaining: remaining)
      end
    end

    # Returns up to 5 dotted keys from the manifest that look similar to the
    # requested key, ranked by shared-prefix length then Levenshtein distance.
    def suggestions_for(key)
      candidates = enumerate.map { |r| r[:key] }
      # Include declared (non-nested) entry keys even if file is missing.
      candidates.concat(@entries.reject(&:nested).map(&:key))
      candidates.uniq!
      Key::Distance.suggest(key, candidates, limit: 5)
    rescue StandardError
      []
    end

    # Enumerate all entry files reachable through the manifest. Returns
    # [{ key:, path:, manifest_entry: }, ...]
    def enumerate(prefix: nil)
      out = @entries.flat_map { |entry| entry.nested ? enumerate_nested(entry) : enumerate_leaf(entry) }
      out.select! { |row| row[:key] == prefix || row[:key].start_with?("#{prefix}.") } if prefix
      out.sort_by { |row| row[:key] }
    end

    def validate_key!(key)
      raise UsageError.new("empty key") if key.nil? || key.empty?

      Key::Grammar.validate!(key)
    end

    private

    def enumerate_leaf(entry)
      fp = resolve_leaf_path(entry)
      File.exist?(fp) ? [{ key: entry.key, path: fp, manifest_entry: entry }] : []
    end

    def enumerate_nested(entry)
      base = File.join(@root, "zones", entry.path)
      return [] unless File.directory?(base)

      glob_pattern = entry.index_filename ? "**/#{entry.index_filename}" : nested_glob(entry.format)
      Dir.glob(File.join(base, glob_pattern)).filter_map { |path| nested_row_for(entry, base, path) }
    end

    def nested_row_for(entry, base, path)
      rel = path.sub(%r{\A#{Regexp.escape(base)}/?}, "")
      stripped = entry.index_filename ? File.dirname(rel) : rel.sub(/#{Regexp.escape(File.extname(rel))}\z/, "")
      segs = stripped.split("/").reject { |s| s.empty? || s == "." }
      return nil if segs.empty?

      illegal = segs.find { |s| !valid_segment?(s) }
      if illegal
        warn("textus: skipping illegal key segment '#{illegal}' at #{path} — run 'textus key normalize --dry-run'")
        return nil
      end

      { key: (entry.key.split(".") + segs).join("."), path: path, manifest_entry: entry }
    end

    def valid_segment?(seg)
      return false if seg.nil? || seg.empty?
      return false if seg.length > Key::Grammar::MAX_SEGMENT_LEN

      seg.match?(Key::Grammar::SEGMENT)
    end

    def validate_declared_keys!
      @entries.each { |e| validate_key!(e.key) }
    end

    def resolve_leaf_path(entry)
      Textus::Key::Path.resolve(self, entry)
    end

    def nested_glob(format)
      Textus::Entry.for_format(format).nested_glob
    end
  end
end
