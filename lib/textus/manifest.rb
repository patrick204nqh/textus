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

    LEGACY_ZONES = {
      "fixed" => ["human"],
      "state" => %w[human ai script],
      "derived" => ["build"],
    }.freeze

    def zones
      @zones ||= begin
        declared = Array(@raw["zones"])
        if declared.empty?
          LEGACY_ZONES.transform_values(&:dup)
        else
          declared.to_h do |z|
            [z["name"], Array(z["writable_by"])]
          end
        end
      end
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
      primary_ext = Entry.for_format(entry.format).extensions.first
      if File.extname(entry.path) == ""
        File.join(@root, "zones", entry.path + primary_ext)
      else
        File.join(@root, "zones", entry.path)
      end
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

  class ManifestEntry
    PUBLISH_EACH_VARS = %w[leaf basename key ext].freeze
    PUBLISH_EACH_VAR_RE = /\{([a-z]+)\}/

    attr_reader :key, :path, :zone, :schema, :owner, :nested, :generator, :raw, :format,
                :projection, :template, :publish_to, :publish_each, :action, :action_config, :ttl, :events,
                :inject_intro

    def initialize(manifest, raw)
      @manifest = manifest
      @raw = raw
      @key = raw["key"] or raise UsageError.new("manifest entry missing key")
      @path = raw["path"] or raise UsageError.new("manifest entry '#{@key}' missing path")
      @zone = raw["zone"] or raise UsageError.new("manifest entry '#{@key}' missing zone")
      @schema = raw["schema"]
      @owner = raw["owner"]
      @nested = raw["nested"] == true
      @generator = raw["generator"]
      @projection = raw["projection"]
      @template = raw["template"]
      @publish_to = Array(raw["publish_to"])
      @publish_each = raw["publish_each"]
      @events = raw["events"] || {}
      @inject_intro = raw["inject_intro"] == true
      @format = resolve_format!(raw["format"])

      reject_legacy!(raw)
      parse_source!(raw["source"])
      validate_format_matrix!
      validate_publish_each!
      validate_inject_intro!
    end

    # Resolves the per-leaf target path (relative to repo root) for a full
    # dotted key under this entry's prefix. Returns nil if this entry has no
    # publish_each template.
    def publish_target_for(full_key)
      return nil if @publish_each.nil?

      entry_segs = @key.split(".")
      key_segs = full_key.split(".")
      raise UsageError.new("key '#{full_key}' is not under entry '#{@key}'") unless key_segs[0, entry_segs.length] == entry_segs

      remaining = key_segs[entry_segs.length..] || []
      leaf = remaining.join("/")
      basename = remaining.last || ""
      ext = Entry.for_format(@format).extensions.first.to_s.sub(/^\./, "")

      vars = { "leaf" => leaf, "basename" => basename, "key" => full_key, "ext" => ext }
      @publish_each.gsub(PUBLISH_EACH_VAR_RE) { vars.fetch(::Regexp.last_match(1)) }
    end

    def derived?
      writers = @manifest.zone_writers(@zone)
      writers.include?("build")
    rescue UsageError => e
      raise UsageError.new("entry '#{@key}': #{e.message}")
    end

    private

    def validate_inject_intro!
      return unless @inject_intro

      unless derived?
        raise UsageError.new(
          "entry '#{@key}': inject_intro: is only valid on derived entries",
        )
      end
      return unless @template.nil?

      raise UsageError.new(
        "entry '#{@key}': inject_intro: requires a template:",
      )
    end

    def validate_publish_each!
      return if @publish_each.nil?

      raise UsageError.new("entry '#{@key}': publish_each requires nested: true") unless @nested
      raise UsageError.new("entry '#{@key}': publish_to and publish_each are mutually exclusive") unless @publish_to.empty?
      raise UsageError.new("entry '#{@key}': publish_each must be a string") unless @publish_each.is_a?(String)

      used_vars = @publish_each.scan(PUBLISH_EACH_VAR_RE).flatten
      unknown = used_vars - PUBLISH_EACH_VARS
      unless unknown.empty?
        raise UsageError.new(
          "entry '#{@key}': publish_each uses unknown template variable(s) " \
          "#{unknown.map { |v| "{#{v}}" }.join(", ")}. Known: #{PUBLISH_EACH_VARS.map { |v| "{#{v}}" }.join(", ")}.",
        )
      end

      required = %w[leaf basename key]
      return if used_vars.any? { |v| required.include?(v) }

      raise UsageError.new(
        "entry '#{@key}': publish_each must reference at least one of {leaf}, {basename}, or {key} " \
        "(else every leaf would clobber the same target).",
      )
    end

    def resolve_format!(declared)
      ext = File.extname(@path)
      inferred = Manifest::EXT_TO_FORMAT[ext]

      if declared.nil?
        return inferred if inferred
        # No extension: nested defaults to markdown, leaf with no ext also markdown.
        return "markdown" if ext == "" && @nested
        return "markdown" if ext == ""
      else
        raise UsageError.new("entry '#{@key}': unknown format #{declared.inspect}") unless Manifest::EXT_TO_FORMAT.values.include?(declared)
        # If the path has an extension, the declared format must match.
        if ext != "" && inferred && inferred != declared
          raise UsageError.new(
            "entry '#{@key}': path extension #{ext.inspect} does not match declared format #{declared.inspect}",
          )
        end
        return declared
      end

      "markdown"
    end

    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    def validate_format_matrix!
      ext = File.extname(@path)

      case @format
      when "markdown"
        # .md, or no extension (will be appended). Anything else is a mismatch caught above.
        raise UsageError.new("entry '#{@key}': markdown format requires '.md' path (got #{ext.inspect})") if ext != "" && ext != ".md"
      when "json"
        if @nested
          # nested json: path is a directory; ext must be empty.
          raise UsageError.new("entry '#{@key}': nested json path must not have an extension") if ext != ""
        elsif ext != ".json"
          raise UsageError.new("entry '#{@key}': json format requires '.json' path (got #{ext.inspect})")
        end
      when "yaml"
        if @nested
          raise UsageError.new("entry '#{@key}': nested yaml path must not have an extension") if ext != ""
        elsif ext != ".yaml" && ext != ".yml"
          raise UsageError.new("entry '#{@key}': yaml format requires '.yaml' or '.yml' path (got #{ext.inspect})")
        end
      when "text"
        if @nested
          raise UsageError.new("entry '#{@key}': nested text path must not have an extension") if ext != ""
        elsif ext != ".txt" && ext != ""
          raise UsageError.new("entry '#{@key}': text format requires '.txt' or no extension (got #{ext.inspect})")
        end
      end

      # Schema rules.
      raise UsageError.new("entry '#{@key}': text format must not declare a schema") if @format == "text" && !@schema.nil?

      # Template-required-for-derived rules. Skipped for entries materialized by an
      # external generator: command (those produce the bytes themselves).
      if derived? && @template.nil? && @generator.nil? &&
         (@format == "markdown" || @format == "text") && !@nested
        raise UsageError.new("entry '#{@key}': derived #{@format} entries require a template")
      end
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

    def parse_source!(src)
      src ||= {}
      @action = src["action"]
      @action_config = src["config"] || {}
      @ttl = src["ttl"]
    end

    def reject_legacy!(raw)
      src = raw["source"] || {}
      if src.key?("parse") || src.key?("from")
        raise UsageError.new(
          "entry '#{@key}': source.parse/source.from removed in 0.2; " \
          "use source.action (+ source.config). See SPEC §5.4.",
        )
      end
      if src.key?("fetcher")
        raise UsageError.new(
          "entry '#{@key}': source.fetcher renamed to source.action in 0.4; " \
          "rename the key. See SPEC §5.4.",
        )
      end
      if raw.key?("hooks")
        raise UsageError.new(
          "entry '#{@key}': 'hooks:' renamed to 'events:' in 0.2; " \
          "remove on_ prefix from event names. See SPEC §5.10.",
        )
      end

      @events.each_key do |evt|
        next if ExtensionRegistry::EVENTS.include?(evt.to_sym)

        raise UsageError.new(
          "entry '#{@key}': unknown event '#{evt}' in events: block. " \
          "Known events: #{ExtensionRegistry::EVENTS.join(", ")}.",
        )
      end
    end
  end
end
