module Textus
  class CLI
    class Verb
      class Rdeps < Verb
        command_name "rdeps"

        def call(store)
          key = positional.shift or raise UsageError.new("rdeps requires a key")
          emit(session_for(store).rdeps(key))
        end
      end
    end
  end
end
