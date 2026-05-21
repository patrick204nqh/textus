module Textus
  class CLI
    class Rdeps < Verb
      def call(store)
        key = positional.shift or raise UsageError.new("rdeps requires a key")
        emit({ "key" => key, "rdeps" => store.rdeps(key) })
      end
    end
  end
end
