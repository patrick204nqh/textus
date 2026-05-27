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

        # Back-compat shims so use-case code that probes .intake_handler/.intake_config
        # keeps working until T6 migrates them to type dispatch.
        def intake_handler = @handler
        def intake_config  = @config
      end
    end
  end
end
