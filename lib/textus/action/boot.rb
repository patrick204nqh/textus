# frozen_string_literal: true

module Textus
  module Action
    class Boot < Base
      extend Textus::Contract::DSL

      verb :boot
      summary "Return the orientation contract: lanes, agent_quickstart, agent_protocol, and pre-computed artifacts."
      surfaces :cli, :mcp

      def initialize
        super()
      end

      def call(container:, **)
        Textus::Boot.build(container: container)
      end
    end
  end
end
