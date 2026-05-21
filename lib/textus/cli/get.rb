module Textus
  class CLI
    class Get < Verb
      def call(store)
        key = positional.shift or raise UsageError.new("get requires a key")
        emit(store.get(key))
      end
    end
  end
end
