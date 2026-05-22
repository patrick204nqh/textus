module Textus
  class CLI
    class Verb
      class Accept < Verb
        option :as_flag, "--as=ROLE"

        def call(store)
          key = positional.shift or raise UsageError.new("accept requires a key")
          ctx = context_for(store)
          emit(Textus::Composition.writes_accept(ctx).call(key))
        end
      end
    end
  end
end
