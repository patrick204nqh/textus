# frozen_string_literal: true

module Textus
  module Dispatch
    # Thin coordinator: Auth -> Ledger -> Executor.
    # Every system interaction flows through fire(event).
    class Gate
      def initialize(container)
        @container = container
        @auth = Auth.new(manifest: container.manifest, schemas: container.schemas)
        @ledger = Ledger.new(container)
        @executor = Executor.new(container)
      end

      def fire(event, session: nil)
        session&.check_etag!(contract_etag) if drift_guarded?(event)
        @auth.check_event!(event) if event.actor
        @ledger.record(event) { @executor.run(event) }
      end

      private

      def contract_etag
        Textus::Etag.for_contract(@container.root)
      end

      def drift_guarded?(event)
        payload = event.payload
        return true unless payload.is_a?(Hash)

        payload.fetch(:__dispatch_check_drift, true)
      end
    end
  end
end
