# frozen_string_literal: true

module Textus
  module Dispatch
    module Actions
      class WriteVerb < Base
        private

        def run_with_cascade(target_key, container:, call:)
          result = yield
          cascade_to_rdeps(target_key, container, call) if target_key
          result
        end

        def cascade_to_rdeps(key, container, call)
          return if derived_write?(key, container)

          rdeps = Textus::Dispatch::Actions::Rdeps.new(key: key).call(container: container, call: call).fetch("rdeps", [])
          producible = rdeps.select { |dep_key| producible?(dep_key, container) }
          return if producible.empty?

          actions = producible.map { |dep_key| Materialize.new(key: dep_key) }
          actions << Observe.new(
            event_name: Textus::Dispatch::Catalog::Events::ENTRY_WRITTEN,
            key: key,
            envelope: nil,
          )

          event = Textus::Dispatch::Event.new(
            name: Textus::Dispatch::Catalog::Events::ENTRY_WRITTEN,
            actor: Textus::Role::AUTOMATION,
            target: key,
            payload: { key: key },
            actions: actions,
            correlation_id: call.correlation_id,
          )
          Textus::Dispatch::Gate.new(container).fire(event)
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
end
