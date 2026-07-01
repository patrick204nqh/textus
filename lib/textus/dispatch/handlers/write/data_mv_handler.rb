module Textus
  module Dispatch
    module Handlers
      module Write
        module DataMvHandler
          module_function

          def call(command, call, deps)
            Textus::UseCases::EntryWrite.data_mv(command, call, deps)
          end
        end
      end
    end
  end
end
