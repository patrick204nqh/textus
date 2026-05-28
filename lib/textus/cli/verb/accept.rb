module Textus
  class CLI
    class Verb
      class Accept < Verb
        command_name "accept"

        option :as_flag, "--as=ROLE"

        def call(store)
          key = positional.shift or raise UsageError.new("accept requires a key")
          emit(session_for(store).accept(key))
        end
      end
    end
  end
end
