module Textus
  class Manifest
    class Policy
      def initialize(data)
        @data    = data
        @entries = nil
      end

      attr_writer :entries

      def writers_for(lane_name)
        Domain::Lane.writers_for(lane_name)
      end

      def proposer_role
        Domain::Lane.proposer_role
      end

      def actor_for(lane_name)
        Domain::Lane.actor_for(lane_name)
      end

        def derived_entry?(key)
          entry = Array(@entries).find { |e| e.key == key }
          entry && entry.lane == "artifacts"
        end

      def queue_lane
        "proposals"
      end

      def machine_lane
        "artifacts"
      end

      def queue_lane?(lane_name)
        lane_name == "proposals"
      end

      def propose_lane_for(role)
        Domain::Lane.propose_lane_for(role)
      end
    end
  end
end
