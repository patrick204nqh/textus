module Textus
  class Manifest
    class Entry
      class Base
        attr_reader :raw, :key, :path, :zone, :schema, :owner, :format, :manifest

        # rubocop:disable Metrics/ParameterLists
        def initialize(manifest:, raw:, key:, path:, zone:, schema:, owner:, format:)
          @manifest = manifest
          @raw = raw
          @key = key
          @path = path
          @zone = zone
          @schema = schema
          @owner = owner
          @format = format
        end
        # rubocop:enable Metrics/ParameterLists

        def kind = self.class.name.split("::").last.downcase.to_sym

        def zone_writers
          @manifest.zone_writers(@zone)
        rescue UsageError => e
          raise UsageError.new("entry '#{@key}': #{e.message}")
        end

        def in_generator_zone? = zone_writers.include?("builder")
        def in_proposal_zone?  = zone_writers.include?("agent")

        def nested?  = false
        def derived? = false
        def intake?  = false
        def leaf?    = false
      end
    end
  end
end
