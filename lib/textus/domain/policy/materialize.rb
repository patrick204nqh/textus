module Textus
  module Domain
    module Policy
      # The `materialize: { on_change }` rule slot (ADR 0087). Selects WHERE a
      # reactive rebuild runs when a derived entry's source changes:
      #   async (default) — after the write, off the critical path
      #   sync            — inline within the write, under the maintenance lock
      class Materialize
        STRATEGIES = %w[async sync].freeze

        attr_reader :on_change

        def initialize(on_change:)
          @on_change = on_change.nil? ? "async" : on_change.to_s
          return if STRATEGIES.include?(@on_change)

          raise Textus::BadManifest.new(
            "materialize.on_change must be one of #{STRATEGIES.join("/")}, got #{@on_change.inspect}",
          )
        end

        def sync? = @on_change == "sync"
      end
    end
  end
end
