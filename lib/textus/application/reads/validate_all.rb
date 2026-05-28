module Textus
  module Application
    module Reads
      class ValidateAll
        def initialize(ctx:, caps:)
          @ctx = ctx
          @caps = caps
          @manifest  = caps.manifest
          @schemas   = caps.schemas
          @audit_log = caps.audit_log
        end

        def call
          Validator.new(
            reader: Get.new(ctx: @ctx, caps: @caps),
            manifest: @manifest,
            audit_log: @audit_log,
            schema_for: ->(name) { @schemas.fetch_or_nil(name) },
          ).call
        end
      end
    end
  end
end
