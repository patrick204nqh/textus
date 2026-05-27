module Textus
  class Manifest
    class Entry
      class Derived < Base
        Projection = Data.define(:select, :pluck, :sort_by, :transform)
        External   = Data.define(:sources, :runner)

        attr_reader :source, :template, :inject_intro, :publish_to, :events

        # rubocop:disable Metrics/ParameterLists
        def initialize(source:, template: nil, inject_intro: false, publish_to: [], events: {},
                       raw_compute: nil, **rest)
          super(**rest)
          @source = source
          @template = template
          @inject_intro = inject_intro
          @publish_to = Array(publish_to)
          @events = events || {}
          # raw_compute stores the original compute hash for backward-compat shims
          @raw_compute = raw_compute
        end
        # rubocop:enable Metrics/ParameterLists

        def derived? = true
        def projection? = @source.is_a?(Projection)
        def external?   = @source.is_a?(External)

        # Back-compat shims so use-case code that probes .projection/.generator/.compute
        # keeps working until T6 migrates them to type dispatch.
        def projection
          projection? ? raw_compute_hash : nil
        end

        def generator
          external? ? raw_compute_hash : nil
        end

        def compute
          @source ? raw_compute_hash : nil
        end

        private

        def raw_compute_hash
          # Prefer the raw compute hash (preserves all original keys).
          # Fall back to reconstructing from the typed source struct.
          return @raw_compute if @raw_compute

          kind_str = projection? ? "projection" : "external"
          @source.to_h.transform_keys(&:to_s).compact.merge("kind" => kind_str)
        end
      end
    end
  end
end
