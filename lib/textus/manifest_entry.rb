module Textus
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

      validate_events!
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

    def validate_events!
      pubsub_events = HookRegistry::EVENTS.select { |_, s| s[:mode] == :pubsub }.keys
      @events.each_key do |evt|
        next if pubsub_events.include?(evt.to_sym)

        raise UsageError.new(
          "entry '#{@key}': unknown event '#{evt}' in events: block. " \
          "Known events: #{pubsub_events.join(", ")}.",
        )
      end
    end
  end
end
