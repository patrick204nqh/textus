module Textus
  class CLI
    class Verb
      class Where < Verb
        command_name "where"

        def call(store)
          key = positional.shift or raise UsageError.new("where requires a key")
          emit(operations_for(store).reads.where.call(key))
        end
      end
    end
  end
end
