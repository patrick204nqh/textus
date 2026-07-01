module Textus
  module Dispatch
    module Handlers
      module MaintenanceHandler
        HANDLES_ALL = Textus::UseCases::Maintenance::HANDLES_ALL
        NEEDS = Textus::UseCases::Maintenance::NEEDS

        module_function

        def call(command, call, deps)
          return Maintenance::DrainHandler.call(command, call, deps) if command.instance_of?(Dispatch::Contracts::DrainStore)
          return Maintenance::JobsHandler.call(command, call, deps) if command.instance_of?(Dispatch::Contracts::JobsAction)

          Textus::UseCases::Maintenance.call(command, call, deps)
        end
      end
    end
  end
end
