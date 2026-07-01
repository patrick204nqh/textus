module Textus
  module Dispatch
    module Handlers
      module MaintenanceHandler
        HANDLES_ALL = Textus::UseCases::Maintenance::HANDLES_ALL
        NEEDS = Textus::UseCases::Maintenance::NEEDS

        module_function

        def call(command, call, deps)
          Textus::UseCases::Maintenance.call(command, call, deps)
        end
      end
    end
  end
end
