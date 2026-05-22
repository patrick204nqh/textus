module Textus
  class CLI
    class Verb
      class RefreshStale < Verb
        option :prefix, "--prefix=KEY"
        option :zone, "--zone=Z"
        option :as_flag, "--as=ROLE"

        def call(store)
          role = Role.resolve(flag: as_flag, env: ENV, root: store.root)
          ctx = Textus::Composition.context(store, role: role)
          result = Textus::Application::Refresh::All.call(ctx, prefix: prefix, zone: zone)
          emit(result)
          exit(1) unless result["ok"]
        end
      end
    end
  end
end
