module Textus
  class Manifest
    class Entry
      class Intake < Base
        attr_reader :handler, :config, :events, :publish_to

        def initialize(handler:, config: {}, events: {}, publish_to: [], **rest)
          super(**rest)
          @handler = handler
          @config = config || {}
          @events = events || {}
          @publish_to = Array(publish_to)
        end

        def intake? = true
      end
    end
  end
end
