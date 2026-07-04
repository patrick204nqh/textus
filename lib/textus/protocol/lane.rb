module Textus
  module Protocol
    module Lane
      def self.handler_for(lane_name)
        ns = lane_name.to_s.split("_").map(&:capitalize).join
        Textus::Lanes.const_get(ns)::Handlers
      rescue NameError
        raise ArgumentError.new("no handler for lane: #{lane_name}")
      end

      PROPOSALS_WRITERS = %w[human agent].freeze

      module_function

      def writers_for(lane_name)
        return PROPOSALS_WRITERS if lane_name == "proposals"

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
        writers_for("proposals").include?(role) ? "scratchpad.proposals" : nil
      end
    end
  end
end
