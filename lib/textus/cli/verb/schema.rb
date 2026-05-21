module Textus
  class CLI
    class Verb
      class Schema < Verb
        def call(store)
          key = positional.shift or raise UsageError.new("schema requires a key")
          emit(store.schema_envelope(key))
        end
      end
    end
  end
end
