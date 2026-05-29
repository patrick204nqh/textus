module Textus
  class CLI
    class Verb
      class Boot < Verb
        command_name "boot"

        def call(store)
          emit(Textus::Boot.build(container: store.container))
        end
      end
    end
  end
end
