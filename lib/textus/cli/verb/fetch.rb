module Textus
  class CLI
    class Verb
      class Fetch < Verb
        option :as_flag, "--as=ROLE"

        def call(store)
          key = positional.shift or raise UsageError.new("fetch requires a key")
          emit(session_for(store).fetch(key).to_h_for_wire)
        end
      end
    end
  end
end
