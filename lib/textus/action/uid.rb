# frozen_string_literal: true

module Textus
  module Action
    class Uid < Base
      extend Textus::Contract::DSL

      verb :uid
      summary "Return the stable UID of an entry without reading its body."
      surfaces :cli
      cli "key uid"
      arg :key, String, required: true, positional: true, description: "entry key"
      view(:cli) { |uid, inputs| { "key" => inputs[:key], "uid" => uid } }

      BURN = :sync

      def initialize(key:)
        super()
        @key = key
      end

      def args = { key: @key }

      def call(container:, call:)
        Textus::Action::Get.new(key: @key).call(container: container, call: call).uid
      end

      def self.new(*args, **kwargs)
        return super(**kwargs) unless args.any?

        positional = instance_method(:initialize).parameters.slice(:keyreq, :key).map(&:last)
        mapped = positional.zip(args).to_h
        super(**mapped.merge(kwargs))
      end
    end
  end
end
