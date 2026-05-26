module Textus
  class CLI
    class Verb
      class Schema < Verb
        def call(store)
          key = positional.shift or raise UsageError.new("schema requires a key")
          emit(operations_for(store).reads.schema_envelope.call(key))
        end
      end
    end
  end
end
