module Textus
  class CLI
    class Stale < Verb
      option :prefix, "--prefix=KEY"
      option :zone, "--zone=Z"

      def call(store)
        emit(store.stale(prefix: prefix, zone: zone))
      end
    end
  end
end
