module Textus
  module Dispatch
    module Handlers
      module ReadHandler
        HANDLES_ALL = Textus::UseCases::EntryRead::HANDLES_ALL
        NEEDS = Textus::UseCases::EntryRead::NEEDS

        module_function

        def call(command, call, deps)
          return Read::GetHandler.call(command, call, deps) if command.instance_of?(Dispatch::Contracts::GetEntry)
          return Read::ListHandler.call(command, call, deps) if command.instance_of?(Dispatch::Contracts::ListKeys)
          return Read::PulseHandler.call(command, call, deps) if command.instance_of?(Dispatch::Contracts::PulseEntries)

          Textus::UseCases::EntryRead.call(command, call, deps)
        end
      end
    end
  end
end
