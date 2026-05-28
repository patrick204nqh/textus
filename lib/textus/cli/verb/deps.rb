module Textus
  class CLI
    class Verb
      class Deps < Verb
        command_name "deps"

        def call(store)
          key = positional.shift or raise UsageError.new("deps requires a key")
          emit({ "key" => key, "deps" => session_for(store).deps(key) })
        end
      end
    end
  end
end
