module Textus
  module Dispatch
    module Handlers
      module Read
        module PulseHandler
          module_function

          def call(command, call, deps)
            Textus::UseCases::EntryRead.pulse_entries(command, call, deps)
          end
        end
      end
    end
  end
end
