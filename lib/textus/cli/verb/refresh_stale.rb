module Textus
  class CLI
    class Verb
      class RefreshStale < Verb
        option :prefix, "--prefix=KEY"
        option :zone, "--zone=Z"
        option :as_flag, "--as=ROLE"

        def call(store)
          ctx = context_for(store)
          result = Textus::Application::Refresh::All.call(ctx, prefix: prefix, zone: zone)
          emit(result)
          result["ok"] ? 0 : 1
        end
      end
    end
  end
end
