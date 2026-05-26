module Textus
  class CLI
    class Verb
      class Rdeps < Verb
        def call(store)
          key = positional.shift or raise UsageError.new("rdeps requires a key")
          emit({ "key" => key, "rdeps" => operations_for(store).reads.rdeps.call(key) })
        end
      end
    end
  end
end
