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
        @data = data
      end

      # The capability a lane's kind requires to be written, or nil if the
      # lane declares no kind. declared_kind returns a Symbol; the table is
      # keyed by String.
      def verb_for_lane(lane_name)
        kind = declared_kind(lane_name)
        kind && Schema::KIND_REQUIRES_VERB[kind.to_s]
      end

      # Names of roles whose declared caps include `verb`.
      def roles_with_capability(verb)
        @data.role_caps.select { |_name, caps| caps.include?(verb) }.keys
      end

      # The conventional automated proposer: a role that can propose but is not
      # the author-anchor (so it resolves to `agent`, not `human`, under the
      # default mapping). Falls back to the first proposer, then nil.
      def proposer_role
        proposers = roles_with_capability("propose")
        (proposers - roles_with_capability("author")).first || proposers.first
      end

      # The role textus acts AS for a system-initiated operation requiring
      # `verb` (no human passed --as). Capability-derived — a role name that
      # exists in the manifest, or nil. Never a hardcoded literal (ADR 0044).
      def actor_for(verb)
        roles_with_capability(verb).first
      end

      # The kind declared on a lane in the manifest, or nil if undeclared.
      def declared_kind(lane_name)
        @data.declared_lane_kinds[lane_name]
      end

      # Lane names declaring `kind` (a Symbol), in manifest order. Lets callers
      # (boot) name a kind's live lane instance(s) instead of hardcoding names.
      def lanes_of_kind(kind)
        @data.declared_lane_kinds.select { |_name, k| k == kind }.keys
      end

      # The single lane declaring `kind: queue`, or nil. Schema guarantees <=1.
      def queue_lane
        @data.declared_lane_kinds.key(:queue)
      end

      # ADR 0091: derived-ness is a property of the ENTRY, not its lane (one
      # machine lane holds both intake and derived entries). Resolve the entry
      # and ask it directly. Returns false if entries are not yet built
      # (validator phase during Data#initialize) — validators must not rely on
      # cross-entry state during construction.
      def derived_entry?(_key)
        false
      end

      # The single lane declaring kind: machine, or nil.
      def machine_lane
        @data.declared_lane_kinds.key(:machine)
      end

      # A lane is a proposal queue iff it declares kind: queue.
      def queue_lane?(lane_name)
        declared_kind(lane_name) == :queue
      end

      # The lane a proposer role writes proposals into: the single lane that
      # declares kind: queue, when the role can write it. Returns nil if there
      # is no queue lane or the role cannot write it.
      def propose_lane_for(role)
        return nil if role.nil?

        q = queue_lane
        return nil unless q

        q_verb = verb_for_lane(q)
        return nil unless roles_with_capability(q_verb).include?(role)

        q
      end
    end
  end
end
