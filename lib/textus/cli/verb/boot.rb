module Textus
  class CLI
    class Verb
      class Boot < Verb
        command_name "boot"

        def call(store)
          emit(Textus::Boot.run(store))
        end
      end
    end
  end
end
