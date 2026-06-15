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

        def intake?     = @source.kind == :intake
        def derived?    = @source.kind == :derived
        def external?   = @source.external?
        def projection? = @source.projection?
        def fetch?      = @source.fetch?
        def derive?     = @source.derive?
        def nested?     = !!@raw["nested"]
        def handler     = @source.handler
        def config      = @source.config

        KIND = :produced

        # ADR 0094/0095: projection (from: project) sources build their DATA
        # artifact here, then publish via the ONE shared mode (Publish::ToPaths).
        # Intake bytes come from Produce::Acquire::Intake and command (external) bytes from the
        # out-of-band runner — neither builds, but both still publish their
        # existing store bytes through the same mode. A projection entry with no
        # targets is a terminal data node: it produced data, so report :built
        # even though nothing was emitted.
        def publish_via(pctx, prefix: nil)
          built = false
          if projection?
            Textus::Produce::Acquire::Projection.new(container: pctx.container, call: pctx.call).run(self)
            built = true
            pctx.emit(:entry_produced, key: @key, envelope: pctx.reader.call(@key), sources: Array(@source.select).compact)
          end
          emitted = publish_mode.publish(pctx, prefix: prefix)
          return emitted if emitted
          return nil unless built

          { kind: :built, value: { "key" => @key, "path" => Key::Path.resolve(pctx.manifest.data, self), "published_to" => [] } }
        end

        def self.from_raw(common, raw)
          new(source: Parser.parse_source(raw, common[:key]), events: raw["events"] || {}, **common)
        end

        Entry::REGISTRY[KIND] = self
      end
    end
  end
end
