module Textus
  module Dispatch
    module Handlers
      module Maintenance
        module DrainHandler
          module_function

          def call(command, call, deps)
            Textus::UseCases::Maintenance.drain_store(command, call, deps)
          end
        end
      end
    end
  end
end
