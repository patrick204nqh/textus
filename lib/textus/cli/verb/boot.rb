module Textus
  class CLI
    class Verb
      class Boot < Verb
        command_name "boot"

        def call(store)
          emit(store.boot)
        end
      end
    end
  end
end
