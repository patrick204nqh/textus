module Textus
  class CLI
    class SchemaMigrate < Verb
      option :rename, "--rename=O:N"

      def call(store)
        name = positional.shift or raise UsageError.new("schema migrate NAME")
        raise UsageError.new("schema migrate requires --rename=OLD:NEW") unless rename

        emit(Textus::SchemaTools.migrate(store, name: name, rename: rename))
      end
    end
  end
end
