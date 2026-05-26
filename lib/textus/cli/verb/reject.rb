module Textus
  class CLI
    class Verb
      class Reject < Verb
        option :as_flag, "--as=ROLE"

        def call(store)
          key = positional.shift or raise UsageError.new("reject requires a key")
          emit(store.writer.reject(key, as: resolved_role(store)))
        end
      end
    end
  end
end
