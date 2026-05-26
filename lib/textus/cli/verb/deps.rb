module Textus
  class CLI
    class Verb
      class Deps < Verb
        command_name "deps"

        def call(store)
          key = positional.shift or raise UsageError.new("deps requires a key")
          emit({ "key" => key, "deps" => operations_for(store).reads.deps.call(key) })
        end
      end
    end
  end
end
