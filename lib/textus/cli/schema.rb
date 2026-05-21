module Textus
  class CLI
    class SchemaVerb < Verb
      def call(store)
        key = positional.shift or raise UsageError.new("schema requires a key")
        emit(store.schema_envelope(key))
      end
    end
  end
end
