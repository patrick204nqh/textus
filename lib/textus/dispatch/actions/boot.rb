# frozen_string_literal: true

module Textus
  module Dispatch
    module Actions
      class Boot < Base
        extend Textus::Contract::DSL

        verb :boot
        summary "Return the orientation contract: zones, entries, schemas, write_flows, agent_quickstart."
        surfaces :cli, :mcp
        arg :lean, :boolean,
            description: "return only orientation essentials (zones, agent_quickstart, contract_etag) for cheap session-start injection"

        BURN = :sync

        def initialize(lean: nil)
          super()
          @lean = lean
        end

        def args
          { lean: @lean }.compact
        end

        def call(container:, **)
          Textus::Boot.build(container: container, lean: !@lean.nil?)
        end
      end
    end
  end
end
