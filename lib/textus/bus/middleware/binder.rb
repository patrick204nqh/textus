module Textus
  module Bus
    module Middleware
      class Binder < Base
        middleware_name :binder

        def call(container:, command:, call:, next_handler:)
          next_handler.call(command, call)
        end
      end
    end
  end
end
