module Textus
  module Dispatch
    module Handlers
      module ReadHandler
        HANDLES_ALL = Textus::UseCases::EntryRead::HANDLES_ALL
        NEEDS = Textus::UseCases::EntryRead::NEEDS

        module_function

        def call(command, call, deps)
          Textus::UseCases::EntryRead.call(command, call, deps)
        end
      end
    end
  end
end
