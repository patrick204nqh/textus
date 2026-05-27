module Textus
  class Manifest
    class Entry
      class Base < Entry
        attr_reader :raw, :key, :path, :zone, :schema, :owner, :format, :manifest

        # rubocop:disable Metrics/ParameterLists, Lint/MissingSuper
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
        # rubocop:enable Metrics/ParameterLists, Lint/MissingSuper

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

        # Legacy field shims — return nil/default so use-cases that probe these attrs keep
        # working until they are migrated to type dispatch (Plan 05 Task 6).
        # rubocop:disable Naming/PredicateMethod
        def publish_target_for(_full_key)
          nil
        end

        def projection
          nil
        end

        def generator
          nil
        end

        def compute
          nil
        end

        def intake_handler
          nil
        end

        def intake_config
          {}
        end

        def template
          nil
        end

        def publish_to
          []
        end

        def publish_each
          @raw["publish_each"]
        end

        def nested
          @raw["nested"] == true
        end

        def index_filename
          @raw["index_filename"]
        end

        def inject_intro
          false
        end

        def events
          {}
        end
        # rubocop:enable Naming/PredicateMethod
      end
    end
  end
end
