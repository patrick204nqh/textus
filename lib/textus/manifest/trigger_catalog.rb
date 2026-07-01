module Textus
  class Manifest
    module TriggerCatalog
      TRIGGERS = %w[
        convergence
        entry.written
        entry.deleted
        entry.moved
        proposal.accepted
        proposal.rejected
      ].freeze

      ACTIONS = %w[materialize sweep index].freeze

      module_function

      def validate_trigger!(token)
        return if TRIGGERS.include?(token)

        raise Textus::BadManifest.new("unknown trigger: #{token}")
      end

      def validate_action!(token)
        return if ACTIONS.include?(token)

        raise Textus::BadManifest.new("unknown action: #{token}")
      end
    end
  end
end
