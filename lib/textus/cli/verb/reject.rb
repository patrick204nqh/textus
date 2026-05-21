module Textus
  class CLI
    class Verb
      class Reject < Verb
        option :as_flag, "--as=ROLE"

        def call(store)
          key = positional.shift or raise UsageError.new("reject requires a key")
          role = Role.resolve(flag: as_flag, env: ENV, root: store.root)
          emit(store.reject(key, as: role))
        end
      end
    end
  end
end
