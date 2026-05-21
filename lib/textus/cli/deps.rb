module Textus
  class CLI
    class Deps < Verb
      def call(store)
        key = positional.shift or raise UsageError.new("deps requires a key")
        emit({ "protocol" => Textus::PROTOCOL, "key" => key, "deps" => store.deps(key) })
      end
    end
  end
end
