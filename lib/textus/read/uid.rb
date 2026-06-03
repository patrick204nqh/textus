module Textus
  module Read
    class Uid
      extend Textus::Contract::DSL

      verb     :uid
      summary  "Return the stable UID of an entry without reading its body."
      surfaces :cli, :ruby
      cli      "key uid"
      arg :key, String, required: true, positional: true, description: "entry key"
      view(:cli) { |uid, inputs| { "key" => inputs[:key], "uid" => uid } }

      def initialize(container:, call:)
        @container = container
        @call      = call
      end

      def call(key)
        get.get(key).uid
      end

      private

      def get
        @get ||= Get.new(container: @container, call: @call)
      end
    end
  end
end
