module Textus
  module Dispatch
    module Handlers
      module WriteHandler
        HANDLES_ALL = Textus::UseCases::EntryWrite::HANDLES_ALL
        NEEDS = Textus::UseCases::EntryWrite::NEEDS

        module_function

        def call(command, call, deps)
          Textus::UseCases::EntryWrite.call(command, call, deps)
        end
      end
    end
  end
end
