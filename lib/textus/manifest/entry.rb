module Textus
  class Manifest
    class Entry
      # Re-exported for backward compatibility with callers that referenced these
      # constants on Entry. Canonical source is the PublishEach validator.
      PUBLISH_EACH_VARS = Validators::PublishEach::KNOWN_VARS
      PUBLISH_EACH_VAR_RE = Validators::PublishEach::VAR_RE

      attr_reader :raw, :key, :path, :zone, :schema, :owner, :nested,
                  :template, :publish_to, :publish_each,
                  :events, :inject_intro, :index_filename, :format,
                  :compute, :projection, :generator,
                  :intake_handler, :intake_config

      # rubocop:disable Metrics/ParameterLists
      def initialize(manifest:, raw:, key:, path:, zone:, schema:, owner:, nested:,
                     template:, publish_to:, publish_each:, events:, inject_intro:,
                     index_filename:, format:, compute:, projection:, generator:,
                     intake_handler:, intake_config:)
        @manifest = manifest
        @raw = raw
        @key = key
        @path = path
        @zone = zone
        @schema = schema
        @owner = owner
        @nested = nested
        @template = template
        @publish_to = publish_to
        @publish_each = publish_each
        @events = events
        @inject_intro = inject_intro
        @index_filename = index_filename
        @format = format
        @compute = compute
        @projection = projection
        @generator = generator
        @intake_handler = intake_handler
        @intake_config = intake_config
      end
      # rubocop:enable Metrics/ParameterLists

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
        ext = Textus::Entry.for_format(@format).extensions.first.to_s.sub(/^\./, "")

        vars = { "leaf" => leaf, "basename" => basename, "key" => full_key, "ext" => ext }
        @publish_each.gsub(PUBLISH_EACH_VAR_RE) { vars.fetch(::Regexp.last_match(1)) }
      end

      # Signal-based zone-kind predicates: derive the "kind" of a zone from its
      # write_policy signals rather than its literal name, so detection keeps
      # working when users rename the default zones.
      def in_generator_zone?
        zone_writers.include?("builder")
      end

      def in_proposal_zone?
        zone_writers.include?("agent")
      end

      private

      def zone_writers
        @manifest.zone_writers(@zone)
      rescue UsageError => e
        raise UsageError.new("entry '#{@key}': #{e.message}")
      end
    end
  end
end
