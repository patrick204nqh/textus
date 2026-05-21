module Textus
  class CLI
    class List < Verb
      option :prefix, "--prefix=KEY"
      option :zone, "--zone=Z"

      def call(store)
        emit({ "protocol" => PROTOCOL, "entries" => store.list(prefix: prefix, zone: zone) })
      end
    end
  end
end
