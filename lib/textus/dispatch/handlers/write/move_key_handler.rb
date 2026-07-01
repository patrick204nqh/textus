module Textus
  module Dispatch
    module Handlers
      module Write
        module MoveKeyHandler
          module_function

          def call(command, call, deps)
            Textus::UseCases::EntryWrite.move_key(command, call, deps)
          end
        end
      end
    end
  end
end
