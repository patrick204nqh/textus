module Textus
  module Dispatch
    module Handlers
      module Maintenance
        module JobsHandler
          module_function

          def call(command, call, deps)
            Textus::UseCases::Maintenance.jobs_action(command, call, deps)
          end
        end
      end
    end
  end
end
