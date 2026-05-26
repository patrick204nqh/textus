module Textus
  module Application
    module Reads
      class ValidateAll
        def initialize(ctx:)
          @ctx = ctx
        end

        def call
          Validator.new(
            reader: Get.new(ctx: @ctx),
            manifest: @ctx.manifest,
            audit_log: @ctx.audit_log,
            schema_for: ->(name) { @ctx.schemas.fetch_or_nil(name) },
          ).call
        end
      end
    end
  end
end
