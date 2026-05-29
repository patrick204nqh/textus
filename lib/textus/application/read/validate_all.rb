module Textus
  module Application
    module Read
      class ValidateAll
        def initialize(container:, call:, hook_context: nil) # rubocop:disable Lint/UnusedMethodArgument
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
end

Textus::Application::UseCase.register(:validate_all, Textus::Application::Read::ValidateAll, caps: :read)
