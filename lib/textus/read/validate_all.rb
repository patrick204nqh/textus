module Textus
  module Read
    class ValidateAll
      def initialize(container:, call:)
        @container = container
        @call      = call
        @manifest  = container.manifest
        @schemas   = container.schemas
        @audit_log = container.audit_log
      end

      def call
        Validator.new(
          reader: GetEntry.new(container: @container, call: @call),
          manifest: @manifest,
          audit_log: @audit_log,
          schema_for: ->(name) { @schemas.fetch_or_nil(name) },
        ).call
      end
    end
  end
end
