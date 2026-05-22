require "yaml"

module Textus
  class Manifest
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

    def permission_for(zone_name)
      Textus::Domain::Permission.new(
        zone: zone_name,
        writable_by: zone_writers(zone_name),
        readable_by: :all,
      )
    end

    def self.load(root)
      manifest_path = File.join(root, "manifest.yaml")
      raise IoError.new("manifest not found: #{manifest_path}") unless File.exist?(manifest_path)

      raw = YAML.safe_load_file(manifest_path, aliases: false)
      unless raw["version"] == PROTOCOL
        msg = if raw["version"] == "textus/1"
                "manifest is textus/1; edit manifest.yaml: change 'version: textus/1' to 'version: #{PROTOCOL}'"
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

      reject_legacy_entry_intake_policy!(Array(raw["entries"]))
      @entries = Array(raw["entries"]).map { |e| Manifest::Entry.new(self, e) }
      validate_declared_keys!
    end

    def policies
      @policies ||= Textus::Manifest::Policies.parse(@raw["policies"] || [])
    end

    def policies_for(key)
      policies.for(key)
    end

    # Returns [Manifest::Entry, resolved_path, remaining_segments]
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

        primary_ext = Textus::Entry.for_format(entry.format).extensions.first
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
      Key::Distance.suggest(key, candidates, limit: 5)
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
              warn("textus: skipping illegal key segment '#{illegal}' at #{fp} — run 'textus key migrate --dry-run'")
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

      Key::Grammar.validate!(key)
    end

    private

    def valid_segment?(seg)
      return false if seg.nil? || seg.empty?
      return false if seg.length > Key::Grammar::MAX_SEGMENT_LEN

      seg.match?(Key::Grammar::SEGMENT)
    end

    def validate_declared_keys!
      @entries.each { |e| validate_key!(e.key) }
    end

    def reject_legacy_entry_intake_policy!(raw_entries)
      raw_entries.each do |re|
        intake = re["intake"]
        next unless intake.is_a?(Hash)
        next unless intake.key?("ttl") || intake.key?("on_stale") || intake.key?("sync_budget_ms")

        raise UsageError.new(
          "entry '#{re["key"]}': intake.ttl/intake.on_stale/intake.sync_budget_ms removed in 0.9.2 — " \
          "move into a top-level policies: block (see CHANGELOG migration recipe).",
        )
      end
    end

    def resolve_leaf_path(entry)
      Textus::Key::Path.resolve(self, entry)
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
