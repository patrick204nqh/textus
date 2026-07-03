module Textus
  module Human
    module Handlers
      def self.loop_status(manifest, active_index: 0)
        Runner.new(manifest).current_node(active_index:)
      end

      def self.loop_advance(manifest, active_index: 0)
        Runner.new(manifest).advance(active_index:)
      end

      def self.evidence_attach(store, node_key, evidence_key, note: nil)
        { node: node_key, evidence: evidence_key, note:, attached_at: Time.now.utc.iso8601 }
      end
    end
  end
end
