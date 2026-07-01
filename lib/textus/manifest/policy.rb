module Textus
  class Manifest
    # Authority over lanes and roles derived from a Manifest::Data snapshot.
    # Encapsulates the lookups previously living on Manifest itself
    # (lane_writers, permission_for). Write authority is derived from
    # capabilities x lane-kind (ADR 0030): each lane-kind requires one verb
    # (Schema::KIND_REQUIRES_VERB) and a role may write a lane iff its caps
    # include that verb (verb_for_lane, roles_with_capability). Derived /
    # proposal-queue status is authoritative via the declared-kind family
    # (declared_kind, derived_entry?, queue_lane?, queue_lane).
    class Policy
      def initialize(data)
        @data    = data
        @entries = nil
      end

      attr_writer :entries

      # The capability a lane's kind requires to be written, or nil if the
      # lane declares no kind. declared_kind returns a Symbol; the table is
      # keyed by String.
      def verb_for_lane(lane_name)
        kind = declared_kind(lane_name)
        kind && Domain::Lane.verb_for(kind)
      end

      def roles_with_capability(verb)
        Domain::Lane.roles_with(verb.to_s, @data.role_caps)
      end

      def proposer_role
        Domain::Lane.proposer_role(@data.role_caps)
      end

      def actor_for(verb)
        Domain::Lane.actor_for(verb.to_s, @data.role_caps)
      end

      def declared_kind(lane_name)
        @data.declared_lane_kinds[lane_name]
      end

      def lanes_of_kind(kind)
        Domain::Lane.lanes_of_kind(kind, @data.declared_lane_kinds)
      end

      def queue_lane
        @data.declared_lane_kinds.key(:queue)
      end

      def derived_entry?(key)
        entry = Array(@entries).find { |e| e.key == key }
        entry.is_a?(Textus::Manifest::Entry::Produced) || false
      end

      def machine_lane
        @data.declared_lane_kinds.key(:machine)
      end

      def queue_lane?(lane_name)
        Domain::Lane.queue_lane?(lane_name, @data.declared_lane_kinds)
      end

      def propose_lane_for(role)
        Domain::Lane.propose_lane_for(
          role, queue_lane, declared_kind(queue_lane), @data.role_caps
        )
      end
    end
  end
end
