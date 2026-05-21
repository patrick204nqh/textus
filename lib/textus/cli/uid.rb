module Textus
  class CLI
    class Uid < Verb
      def call(store)
        key = positional.shift or raise UsageError.new("uid requires a key")
        emit({ "protocol" => PROTOCOL, "key" => key, "uid" => store.uid(key) })
      end
    end
  end
end
