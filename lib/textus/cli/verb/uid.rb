module Textus
  class CLI
    class Verb
      class Uid < Verb
        def call(store)
          key = positional.shift or raise UsageError.new("uid requires a key")
          emit({ "key" => key, "uid" => operations_for(store).reads.uid.call(key) })
        end
      end
    end
  end
end
