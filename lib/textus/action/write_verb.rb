# frozen_string_literal: true

module Textus
  module Action
    class WriteVerb < Base
      private

      def auth(container)
        Textus::Gate::Auth.new(container)
      end

      def writer(container, call)
        Textus::Envelope::Writer.from(container: container, call: call)
      end

      def reader(container)
        Textus::Envelope::Reader.from(container: container)
      end

      def run_with_cascade(target_key, container:, call:)
        result = yield
        cascade_to_rdeps(target_key, container, call) if target_key
        result
      end

      def cascade_to_rdeps(key, container, call)
        rdeps = Textus::Action::Rdeps.new(key: key).call(container: container, call: call).fetch("rdeps", [])
        producible = rdeps.select { |dep_key| producible?(dep_key, container) }
        return if producible.empty?

        producible.each do |dep_key|
          Textus::Store::Jobs::Materialize.new(key: dep_key).call(container:, call:)
        end
      end

      def producible?(key, container)
        entry = container.manifest.resolver.resolve(key).entry
        !entry.publish_tree.nil?
      rescue Textus::Error
        false
      end
    end
  end
end
