module Textus
  module Surfaces
    class CLI
      class Verb
        class SchemaMigrate < Verb
          command_name "migrate"
          parent_group Group::Schema

          option :rename, "--rename=O:N"

          def call(store)
            name = positional.shift or raise UsageError.new("schema migrate NAME")
            raise UsageError.new("schema migrate requires --rename=OLD:NEW") unless rename

            emit(Textus::Schema::Tools.migrate(store, name: name, rename: rename))
          end
        end
      end
    end
  end
end
