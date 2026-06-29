module Textus
  module Dispatch
    module Middleware
      class Binder < Base
        middleware_name :binder

        def call(container:, command:, call:, next_handler:) # rubocop:disable Lint/UnusedMethodArgument
          return next_handler.call(command, call) unless command.is_a?(Dispatch::Binder::Pending)

          spec = command.spec
          contract_class = VerbRegistry.contract_class_for(spec.verb) or
            raise Textus::UsageError.new("unknown command verb: #{spec.verb}")
          resolved = Dispatch::Binder.bind(spec, command.inputs)
          built = Dispatch::Pipeline.build_command(contract_class, resolved)
          next_handler.call(built, call)
        end
      end
    end
  end
end
