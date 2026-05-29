module Textus
  class CLI
    class Verb
      class Retain < Verb
        command_name "retain"

        option :prefix, "--prefix=KEY"
        option :zone, "--zone=Z"
        option :as_flag, "--as=ROLE"

        def call(store)
          result = session_for(store).retention_sweep(prefix: prefix, zone: zone)
          emit(result)
          result["ok"] ? 0 : 1
        end
      end
    end
  end
end
