module Textus
  class CLI
    class Verb
      class List < Verb
        command_name "list"

        option :prefix, "--prefix=KEY"
        option :zone, "--zone=Z"

        def call(store)
          emit({ "entries" => operations_for(store).reads.list.call(prefix: prefix, zone: zone) })
        end
      end
    end
  end
end
