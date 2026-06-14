# frozen_string_literal: true

module Textus
  module Action
    class WriteVerb < Base
      private

      def run_with_cascade(target_key, container:, call:)
        result = yield
        cascade_to_rdeps(target_key, container, call) if target_key
        result
      end

      def cascade_to_rdeps(key, container, call)
        return if derived_write?(key, container)

        rdeps = Textus::Action::Rdeps.new(key: key).call(container: container, call: call).fetch("rdeps", [])
        producible = rdeps.select { |dep_key| producible?(dep_key, container) }
        return if producible.empty?

        producible.each do |dep_key|
          Textus::Action::Background::Materialize.new(key: dep_key).call(container:, call:)
        end
        Textus::Action::Observe.new(
          event_name: Textus::Events::ENTRY_WRITTEN,
          key: key,
          envelope: nil,
        ).call(container:, call:)
      end

      def derived_write?(key, container)
        container.manifest.resolver.resolve(key).entry.derived?
      rescue Textus::Error
        false
      end

      def producible?(key, container)
        entry = container.manifest.resolver.resolve(key).entry
        entry.derived? || !entry.publish_tree.nil?
      rescue Textus::Error
        false
      end
    end
  end
end
