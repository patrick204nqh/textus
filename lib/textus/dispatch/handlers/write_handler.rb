module Textus
  module Dispatch
    module Handlers
      module WriteHandler
        HANDLES_ALL = Textus::UseCases::EntryWrite::HANDLES_ALL
        NEEDS = Textus::UseCases::EntryWrite::NEEDS

        module_function

        def call(command, call, deps)
          return Write::PutHandler.call(command, call, deps) if command.instance_of?(Dispatch::Contracts::PutEntry)
          return Write::MoveKeyHandler.call(command, call, deps) if command.instance_of?(Dispatch::Contracts::MoveKey)
          return Write::DeleteKeyHandler.call(command, call, deps) if command.instance_of?(Dispatch::Contracts::DeleteKey)
          return Write::DataMvHandler.call(command, call, deps) if command.instance_of?(Dispatch::Contracts::DataMv)

          Textus::UseCases::EntryWrite.call(command, call, deps)
        end
      end
    end
  end
end
