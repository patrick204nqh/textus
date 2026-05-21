module Textus
  class CLI
    class Verb
      class Where < Verb
        def call(store)
          key = positional.shift or raise UsageError.new("where requires a key")
          emit(store.where(key))
        end
      end
    end
  end
end
