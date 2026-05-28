module Textus
  class CLI
    class Verb
      class Refresh < Verb
        option :as_flag, "--as=ROLE"

        def call(store)
          key = positional.shift or raise UsageError.new("refresh requires a key")
          emit(session_for(store).refresh(key).to_h_for_wire)
        end
      end
    end
  end
end
