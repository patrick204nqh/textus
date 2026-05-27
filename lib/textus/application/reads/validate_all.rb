module Textus
  module Application
    module Reads
      class ValidateAll
        def initialize(ctx:, manifest:, file_store:, schemas:, audit_log:)
          @ctx        = ctx
          @manifest   = manifest
          @file_store = file_store
          @schemas    = schemas
          @audit_log  = audit_log
        end

        def call
          Validator.new(
            reader: Get.new(ctx: @ctx, manifest: @manifest, file_store: @file_store),
            manifest: @manifest,
            audit_log: @audit_log,
            schema_for: ->(name) { @schemas.fetch_or_nil(name) },
          ).call
        end
      end
    end
  end
end
