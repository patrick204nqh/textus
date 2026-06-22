module Textus
  module Bus
    module Middleware
      class Binder < Base
        middleware_name :binder

        def call(command, call, next_handler)
          next_handler.call(command)
        end
      end
    end
  end
end
