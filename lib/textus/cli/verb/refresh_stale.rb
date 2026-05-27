module Textus
  class CLI
    class Verb
      class RefreshStale < Verb
        command_name "stale"
        parent_group Group::Refresh

        option :prefix, "--prefix=KEY"
        option :zone, "--zone=Z"
        option :as_flag, "--as=ROLE"

        def call(store)
          result = operations_for(store).refresh_all(prefix: prefix, zone: zone)
          emit(result)
          result["ok"] ? 0 : 1
        end
      end
    end
  end
end
