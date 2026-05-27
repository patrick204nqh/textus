module Textus
  class Manifest
    class Entry
      class Base < Entry
        attr_reader :raw, :key, :path, :zone, :schema, :owner, :format, :manifest, :publish_to

        # rubocop:disable Metrics/ParameterLists, Lint/MissingSuper
        def initialize(manifest:, raw:, key:, path:, zone:, schema:, owner:, format:, publish_to: [])
          @manifest = manifest
          @raw = raw
          @key = key
          @path = path
          @zone = zone
          @schema = schema
          @owner = owner
          @format = format
          @publish_to = Array(publish_to)
        end
        # rubocop:enable Metrics/ParameterLists, Lint/MissingSuper

        def kind = self.class.name.split("::").last.downcase.to_sym

        def zone_writers
          @manifest.zone_writers(@zone)
        rescue UsageError => e
          raise UsageError.new("entry '#{@key}': #{e.message}")
        end

        def in_generator_zone? = @manifest.zone_kinds(@zone).include?(:generator)
        def in_proposal_zone?  = @manifest.zone_kinds(@zone).include?(:proposer)

        def nested?  = false
        def derived? = false
        def intake?  = false
        def leaf?    = false

        # Nil stubs for cross-cutting optional attrs. Subclasses override the
        # ones they own. Validators and serializers can call these directly
        # without `respond_to?` guards.
        def template       = nil
        def inject_boot    = false # rubocop:disable Naming/PredicateMethod
        def events         = {}
        def publish_each   = nil
        def index_filename = nil
      end
    end
  end
end
