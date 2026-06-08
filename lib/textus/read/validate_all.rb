module Textus
  module Read
    # Store-wide schema + role-authority validation: walks every entry and runs
    # the Validator over it. Consumed internally by `doctor`'s schema_violations
    # check and exposed as a Ruby store method (`store.validate_all`).
    #
    # Ruby-only, like `Read::Freshness`: it declares a contract (so it round-trips
    # through the routing<->contract bijection, ADR 0105) but omits `surfaces`, so
    # it gets no CLI or MCP projection. The public `validate-all` CLI verb was
    # removed in v0.5 (`doctor --check=schema_violations` replaces it).
    class ValidateAll
      extend Textus::Contract::DSL

      verb    :validate_all
      summary "Internal store-wide schema + role-authority validation; backs " \
              "doctor's schema_violations check. No public surface (ADR 0105)."

      def initialize(container:, call:)
        @container = container
        @call      = call
        @manifest  = container.manifest
        @schemas   = container.schemas
        @audit_log = container.audit_log
      end

      def call
        Validator.new(
          reader: Get.new(container: @container, call: @call),
          manifest: @manifest,
          audit_log: @audit_log,
          schema_for: ->(name) { @schemas.fetch_or_nil(name) },
        ).call
      end
    end
  end
end
