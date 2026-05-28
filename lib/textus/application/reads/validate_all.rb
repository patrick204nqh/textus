module Textus
  module Application
    module Reads
      class ValidateAll
        def initialize(ctx:, ports:)
          @ctx     = ctx
          @ports   = ports
          @manifest  = ports.manifest
          @schemas   = ports.schemas
          @audit_log = ports.audit_log
        end

        def call
          Validator.new(
            reader: Get.new(ctx: @ctx, ports: @ports),
            manifest: @manifest,
            audit_log: @audit_log,
            schema_for: ->(name) { @schemas.fetch_or_nil(name) },
          ).call
        end
      end
    end
  end
end
