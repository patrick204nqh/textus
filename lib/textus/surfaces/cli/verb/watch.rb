module Textus
  module Surfaces
    class CLI
      class Verb
        class Watch < Verb
          command_name "watch"

          def call(store)
            call = Textus::Call.build(role: Textus::Role::AUTOMATION)
            Textus::Dispatch::Runtime::Watch.new(container: store.container, call: call).run
            0
          end
        end
      end
    end
  end
end
