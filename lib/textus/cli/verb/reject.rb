module Textus
  class CLI
    class Verb
      class Reject < Verb
        command_name "reject"

        option :as_flag, "--as=ROLE"

        def call(store)
          key = positional.shift or raise UsageError.new("reject requires a key")
          emit(session_for(store).reject(key))
        end
      end
    end
  end
end
