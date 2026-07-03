module Textus
  module Protocol
    module Lane
      def self.handler_for(lane_name)
        ns = lane_name.to_s.split("_").map(&:capitalize).join
        Textus.const_get(ns)::Handlers
      rescue NameError
        raise ArgumentError, "no handler for lane: #{lane_name}"
      end

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
