module Textus
  class CLI
    class Verb
      class Accept < Verb
        option :as_flag, "--as=ROLE"

        def call(store)
          key = positional.shift or raise UsageError.new("accept requires a key")
          role = Role.resolve(flag: as_flag, env: ENV, root: store.root)
          ctx = Textus::Composition.context(store, role: role)
          emit(Textus::Composition.writes_accept(ctx).call(key))
        end
      end
    end
  end
end
