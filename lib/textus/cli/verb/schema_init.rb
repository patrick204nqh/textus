module Textus
  class CLI
    class Verb
      class SchemaInit < Verb
        option :from_key, "--from=KEY"

        def call(store)
          name = positional.shift or raise UsageError.new("schema init NAME")
          raise UsageError.new("schema init requires --from=KEY") unless from_key

          emit(Textus::Schema::Tools.init(store, name: name, from: from_key))
        end
      end
    end
  end
end
