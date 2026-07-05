module Textus
  module Protocol
    module Lane
      def self.handler_for(lane_name)
        ns = lane_name.to_s.split("_").map(&:capitalize).join
        Textus::Lanes.const_get(ns)::Handlers
      rescue NameError
        raise ArgumentError.new("no handler for lane: #{lane_name}")
      end
    end
  end
end
