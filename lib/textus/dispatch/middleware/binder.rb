module Textus
  module Dispatch
    module Middleware
      class Binder < Base
        middleware_name :binder

        def call(container:, command:, call:, next_handler:) # rubocop:disable Lint/UnusedMethodArgument
          return next_handler.call(command, call) unless command.is_a?(Dispatch::Binder::Pending)

          spec = command.spec
          contract_class = VerbRegistry::VERB_TO_CONTRACT.fetch(spec.verb) do
            raise Textus::UsageError.new("unknown command verb: #{spec.verb}")
          end
          resolved = Dispatch::Binder.bind(spec, command.inputs, session: command.session)
          built = Dispatch::Pipeline.build_command(contract_class, resolved)
          next_handler.call(built, call)
        end
      end
    end
  end
end
