module Textus
  class CLI
    class Verb
      class List < Verb
        command_name "list"

        option :prefix, "--prefix=KEY"
        option :zone, "--zone=Z"

        def call(store)
          emit({ "entries" => session_for(store).list(prefix: prefix, zone: zone) })
        end
      end
    end
  end
end
