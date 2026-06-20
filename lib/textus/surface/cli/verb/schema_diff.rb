module Textus
  module Surface
    class CLI
      class Verb
        class SchemaDiff < Verb
          command_name "diff"
          parent_group Group::Schema

          def call(store)
            name = positional.shift or raise UsageError.new("schema diff NAME")
            emit(Textus::Schema::Tools.diff(store, name: name))
          end
        end
      end
    end
  end
end
