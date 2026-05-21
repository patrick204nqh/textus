module Textus
  class CLI
    class SchemaDiff < Verb
      prepend DeprecatedAliasMixin

      def self.deprecated_name = "schema-diff"
      def self.replacement_path = "schema diff"

      def call(store)
        name = positional.shift or raise UsageError.new("schema-diff NAME")
        emit(Textus::SchemaTools.diff(store, name: name))
      end
    end
  end
end
