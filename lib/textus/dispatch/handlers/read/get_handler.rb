module Textus
  module Dispatch
    module Handlers
      module Read
        module GetHandler
          module_function

          def call(command, _call, deps)
            Textus::UseCases::EntryRead.get_entry(command, deps)
          end
        end
      end
    end
  end
end
