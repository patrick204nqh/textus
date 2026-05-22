module Textus
  class CLI
    class Verb
      class Refresh < Verb
        option :as_flag, "--as=ROLE"

        def call(store)
          key = positional.shift or raise UsageError.new("refresh requires a key")
          role = Role.resolve(flag: as_flag, env: ENV, root: store.root)
          ctx = Textus::Composition.context(store, role: role)
          emit(Textus::Composition.refresh_worker(ctx).run(key))
        end
      end
    end
  end
end
