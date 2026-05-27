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

        def intake? = true
      end
    end
  end
end
