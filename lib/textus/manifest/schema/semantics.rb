# frozen_string_literal: true

require_relative "semantics/invariants"
require_relative "semantics/migration"
require_relative "semantics/cross_field"

module Textus
  class Manifest
    module Schema
      # Cross-field rules and ADR migration hints. Called by Validator.validate!
      # AFTER the structural dry-schema Contract passes. Operates on the raw hash.
      module Semantics
        extend Invariants
        extend Migration
        extend CrossField

        module_function

        def check!(raw)
          check_migration!(raw)
          check_invariants!(raw)
          check_cross_field!(raw)
        end
      end
    end
  end
end
