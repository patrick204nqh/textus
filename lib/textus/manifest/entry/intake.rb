module Textus
  class Manifest
    class Entry
      class Intake < Base
        attr_reader :source, :events

        def initialize(source:, events: {}, **rest)
          super(**rest)
          @source = source
          @events = events || {}
        end

        def intake?  = true
        def nested?  = !!@raw["nested"]
        def handler  = @source.handler
        def config   = @source.config

        KIND = :intake

        def self.from_raw(common, raw)
          source = Parser.parse_source(raw, common[:key])
          raise UsageError.new("entry '#{common[:key]}' kind: intake needs source.from: handler") unless source.kind == :intake

          new(source: source, events: raw["events"] || {}, **common)
        end

        Entry::REGISTRY[KIND] = self
      end
    end
  end
end
