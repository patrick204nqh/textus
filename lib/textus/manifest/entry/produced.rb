module Textus
  class Manifest
    class Entry
      # A produced entry (ADR 0095) — anything with a `source:`. The produce
      # method (intake/derived/external) is read from source.from; there is no
      # separate kind for it. Merges the former Derived + Intake classes.
      class Produced < Base
        attr_reader :source, :events

        def initialize(source:, events: {}, **rest)
          super(**rest)
          @source = source
          @events = events || {}
        end

        def intake?     = false
        def derived?    = false
        def external?   = @source&.external? || false
        def projection? = false
        def fetch?      = false
        def derive?     = false
        def nested?     = !!@raw["nested"]
        def handler     = nil
        def config      = @source.respond_to?(:config) ? @source.config : nil

        KIND = :produced

        # Publish existing store bytes via the shared publish mode (Publish::ToPaths
        # or Publish::None). Workflow runners handle the produce step; this method
        # only publishes whatever bytes are already on disk.
        def publish_via(pctx, prefix: nil)
          publish_mode.publish(pctx, prefix: prefix)
        end

        def self.from_raw(common, raw)
          new(source: Parser.parse_source(raw, common[:key]), events: raw["events"] || {}, **common)
        end

        Entry::REGISTRY[KIND] = self
      end
    end
  end
end
