module Textus
  class CLI
    class Uid < Verb
      prepend DeprecatedAliasMixin

      def self.deprecated_name = "uid"
      def self.replacement_path = "key uid"

      def call(store)
        key = positional.shift or raise UsageError.new("uid requires a key")
        emit({ "key" => key, "uid" => store.uid(key) })
      end
    end
  end
end
