module Textus
  class CLI
    class List < Verb
      option :prefix, "--prefix=KEY"
      option :zone, "--zone=Z"

      def call(store)
        emit({ "entries" => store.list(prefix: prefix, zone: zone) })
      end
    end
  end
end
