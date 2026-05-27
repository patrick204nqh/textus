module Textus
  class Manifest
    class Entry
      class Intake < Base
        attr_reader :handler, :config, :events

        def initialize(handler:, config: {}, events: {}, **rest)
          super(**rest)
          @handler = handler
          @config = config || {}
          @events = events || {}
        end

        def intake?  = true
        def nested?  = !!@raw["nested"]

        KIND = :intake

        def self.from_raw(common, raw)
          intake = raw["intake"] || {}
          handler = intake["handler"] || raw["intake_handler"] or
            raise UsageError.new("intake entry '#{common[:key]}' missing handler")
          config = intake["config"] || raw["intake_config"] || {}
          new(handler: handler, config: config, events: raw["events"] || {}, **common)
        end

        Entry::REGISTRY[KIND] = self
      end
    end
  end
end
