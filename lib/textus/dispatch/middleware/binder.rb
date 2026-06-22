module Textus
  module Dispatch
    module Middleware
      class Binder < Base
        middleware_name :binder

        def call(container:, command:, call:, next_handler:) # rubocop:disable Lint/UnusedMethodArgument
          next_handler.call(command, call)
        end
      end
    end
  end
end
