module Textus
  module Dispatch
    module Handlers
      module Write
        module PutHandler
          module_function

          def call(command, call, deps)
            Textus::UseCases::EntryWrite.put_entry(command, call, deps)
          end
        end
      end
    end
  end
end
