module Textus
  module Dispatch
    module Handlers
      module Read
        module ListHandler
          module_function

          def call(command, _call, deps)
            Textus::UseCases::EntryRead.list_keys(command, deps)
          end
        end
      end
    end
  end
end
