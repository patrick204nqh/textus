module Textus
  module Dispatch
    module Handlers
      module Write
        module DeleteKeyHandler
          module_function

          def call(command, call, deps)
            Textus::UseCases::EntryWrite.delete_key(command, call, deps)
          end
        end
      end
    end
  end
end
