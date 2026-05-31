module Textus
  class CLI
    class Verb
      class Schema < Verb
        command_name "show"
        parent_group Group::Schema

        def call(store)
          key = positional.shift or raise UsageError.new("schema requires a key")
          emit(session_for(store).schema(key))
        end
      end
    end
  end
end
