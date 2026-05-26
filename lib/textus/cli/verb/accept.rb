module Textus
  class CLI
    class Verb
      class Accept < Verb
        option :as_flag, "--as=ROLE"

        def call(store)
          key = positional.shift or raise UsageError.new("accept requires a key")
          emit(operations_for(store).writes.accept.call(key))
        end
      end
    end
  end
end
