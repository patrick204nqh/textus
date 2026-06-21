# frozen_string_literal: true

module Textus
  module Action
    class Uid < Base
      verb :uid
      summary "Return the stable UID of an entry without reading its body."
      surfaces :cli
      cli "key uid"
      arg :key, String, required: true, positional: true, description: "entry key"
      view(:cli) { |uid, inputs| { "key" => inputs[:key], "uid" => uid } }

      def self.call(container:, call:, key:)
        Textus::Action::Get.call(container: container, call: call, key: key).uid
      end
    end
  end
end
