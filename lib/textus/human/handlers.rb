module Textus
  module Human
    module Handlers
      module_function

      def propose(key:, meta: nil, body: nil, content: nil, container:, call:)
        zone = container.manifest.policy.propose_lane_for(call.role)
        return { error: { code: "propose_forbidden", message: "role '#{call.role}' has no writable propose_lane" } } unless zone

        full_key = "#{zone}.#{key}"
        mentry = container.manifest.resolver.resolve(full_key).entry
        env = container.writer.put(
          full_key, mentry:, call:,
          payload: Textus::Value::Payload.new(meta: meta || {}, body:, content:)
        )
        env.to_h_for_wire
      end

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
