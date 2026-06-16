module Textus
  class Manifest
    class Entry
      # A produced entry — `kind: produced` with an optional `source:` block.
      # When `source:` is present it must be `from: external` (out-of-band
      # generator; textus detects drift but never runs it). When absent the
      # entry is produced by a workflow file in .textus/workflows/.
      class Produced < Base
        attr_reader :source

        def initialize(source:, **rest)
          super(**rest)
          @source = source
        end

        def external? = @source&.external? || false
        def nested?   = !!@raw["nested"]

        KIND = :produced

        # Publish existing store bytes via the shared publish mode (Publish::ToPaths
        # or Publish::None). Workflow runners handle the produce step; this method
        # only publishes whatever bytes are already on disk.
        def publish_via(pctx, prefix: nil)
          publish_mode.publish(pctx, prefix: prefix)
        end

        def self.from_raw(common, raw)
          new(source: Parser.parse_source(raw, common[:key]), **common)
        end

        Entry::REGISTRY[KIND] = self
      end
    end
  end
end
