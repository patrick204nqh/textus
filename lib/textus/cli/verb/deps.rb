module Textus
  class CLI
    class Verb
      class Deps < Verb
        def call(store)
          key = positional.shift or raise UsageError.new("deps requires a key")
          emit({ "key" => key, "deps" => store.deps(key) })
        end
      end
    end
  end
end
