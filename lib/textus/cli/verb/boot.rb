module Textus
  class CLI
    class Verb
      class Boot < Verb
        command_name "boot"

        def call(store)
          emit(Textus::Boot.run_via(container: store.container, role: Textus::Role::DEFAULT))
        end
      end
    end
  end
end
