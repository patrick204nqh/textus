# frozen_string_literal: true

module Textus
  module Action
    class Boot < Base

      verb :boot
      summary "Return the orientation contract: lanes, agent_quickstart, agent_protocol, and pre-computed artifacts."
      surfaces :cli, :mcp

      def self.call(container:, **)
        Textus::Boot.build(container: container)
      end
    end
  end
end
