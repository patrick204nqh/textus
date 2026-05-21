module Textus
  class CLI
    class RefreshVerb < Verb
      option :as_flag, "--as=ROLE"

      def call(store)
        key = positional.shift or raise UsageError.new("refresh requires a key")
        role = Role.resolve(flag: as_flag, env: ENV, root: store.root)
        emit(Textus::Refresh.call(store, key, as: role))
      end
    end
  end
end
