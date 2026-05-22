module Textus
  class CLI
    class Verb
      class RefreshStale < Verb
        option :prefix, "--prefix=KEY"
        option :zone, "--zone=Z"
        option :as_flag, "--as=ROLE"

        def call(store)
          role = Role.resolve(flag: as_flag, env: ENV, root: store.root)
          result = Textus::Refresh.refresh_stale(store, prefix: prefix, zone: zone, as: role)
          emit(result)
          exit(1) unless result["ok"]
        end
      end
    end
  end
end
