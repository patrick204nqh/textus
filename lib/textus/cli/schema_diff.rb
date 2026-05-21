module Textus
  class CLI
    class SchemaDiff < Verb
      def call(store)
        name = positional.shift or raise UsageError.new("schema diff NAME")
        emit(Textus::Schema::Tools.diff(store, name: name))
      end
    end
  end
end
