module Textus
  module Protocol
    class Manifest
      class Policy
        PROPOSALS_WRITERS = %w[human agent].freeze

        def initialize(data)
          @data    = data
          @entries = nil
        end

        attr_writer :entries

        # ── Authorization ──

        def allowed?(role:, lane:)
          writers_for(lane).map(&:to_sym).include?(role.to_sym)
        end

        def allowed!(role:, lane:, key: nil)
          return true if allowed?(role:, lane:)

          raise Textus::WriteForbidden.new(key, lane, holders: writers_for(lane))
        end

        def writers_for(lane_name)
          return PROPOSALS_WRITERS if lane_name == "proposals"

          lane_map = Textus::Protocol::V4::LANES[lane_name]
          lane_map ? Array(lane_map[:writers]) : []
        end

        def actor_for(lane_name)
          writers_for(lane_name).first
        end

        def proposer_role
          proposers = writers_for("proposals")
          authors = writers_for("knowledge")
          (proposers - authors).first || proposers.first
        end

        # ── Existing methods (unchanged) ──

        def derived_entry?(key)
          entry = Array(@entries).find { |e| e.key == key }
          entry && entry.lane == "artifacts"
        end

        def queue_lane
          "scratchpad.proposals"
        end

        def machine_lane
          "artifacts"
        end

        def queue_lane?(lane_name)
          lane_name == "scratchpad"
        end

        def propose_lane_for(role)
          proposers = writers_for("proposals")
          proposers.include?(role) ? "scratchpad.proposals" : nil
        end
      end
    end
  end
end
