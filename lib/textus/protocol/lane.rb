module Textus
  module Protocol
    module Lane
      module_function

      def writers_for(lane_name)
        Textus::Protocol::V4::LANES.dig(lane_name, :writers) || []
      end

      def proposer_role
        proposers = writers_for("proposals")
        authors = writers_for("knowledge")
        (proposers - authors).first || proposers.first
      end

      def actor_for(lane_name)
        writers_for(lane_name).first
      end

      def propose_lane_for(role)
        writers_for("proposals").include?(role) ? "proposals" : nil
      end
    end
  end
end
