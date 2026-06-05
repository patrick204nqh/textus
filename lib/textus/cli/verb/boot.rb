module Textus
  class CLI
    class Verb
      class Boot < Verb
        command_name "boot"
        option :lean, "--lean"

        def call(store)
          emit(store.boot(lean: !!lean))
        end
      end
    end
  end
end
