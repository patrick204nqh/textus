module Textus
  module Domain
    module Lane
      LANE_VERBS = {
        "canon" => "author",
        "workspace" => "keep",
        "machine" => "converge",
        "queue" => "propose",
        "raw" => "ingest",
      }.freeze

      module_function

      def verb_for(kind)
        LANE_VERBS[kind.to_s]
      end

      def roles_with(verb, role_caps)
        role_caps.select { |_name, caps| caps.include?(verb) }.keys
      end

      def writers_for(lane_name, declared_kinds, role_caps)
        kind = declared_kinds[lane_name]
        return [] unless kind

        verb = verb_for(kind)
        return [] unless verb

        roles_with(verb, role_caps)
      end

      def proposer_role(role_caps)
        proposers = roles_with("propose", role_caps)
        authors = roles_with("author", role_caps)
        (proposers - authors).first || proposers.first
      end

      def actor_for(verb, role_caps)
        roles_with(verb, role_caps).first
      end

      def propose_lane_for(role, queue_lane, queue_kind, role_caps)
        return nil unless queue_lane && queue_kind

        verb = verb_for(queue_kind)
        return nil unless verb && roles_with(verb, role_caps).include?(role)

        queue_lane
      end

      def queue_lane?(lane_name, declared_kinds)
        declared_kinds[lane_name] == :queue
      end

      def lanes_of_kind(kind, declared_kinds)
        declared_kinds.select { |_name, k| k == kind }.keys
      end
    end
  end
end
