module Textus
  module Dispatch
    module Handlers
      module WriteHandler
        HANDLES_ALL = Textus::UseCases::EntryWrite::HANDLES_ALL
        NEEDS = Textus::UseCases::EntryWrite::NEEDS

        module_function

        def call(command, call, deps)
          return Write::PutHandler.call(command, call, deps) if command.instance_of?(Dispatch::Contracts::PutEntry)

          Textus::UseCases::EntryWrite.call(command, call, deps)
        end
      end
    end
  end
end
