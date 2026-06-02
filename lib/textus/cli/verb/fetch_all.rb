module Textus
  class CLI
    class Verb
      class FetchAll < Verb
        command_name "all"
        parent_group Group::Fetch

        option :prefix, "--prefix=KEY"
        option :zone, "--zone=Z"
        option :as_flag, "--as=ROLE"

        def call(store)
          result = session_for(store).fetch_all(prefix: prefix, zone: zone)
          emit(result)
          result["ok"] ? 0 : 1
        end
      end
    end
  end
end
