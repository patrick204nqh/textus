module Textus
  module Application
    module Reads
      module ValidateAll
        def self.call(*, session:, ctx:, caps:, **) # rubocop:disable Lint/UnusedMethodArgument
          Impl.new(ctx: ctx, caps: caps).call(*, **)
        end

        class Impl
          def initialize(ctx:, caps:)
            @ctx = ctx
            @caps = caps
            @manifest  = caps.manifest
            @schemas   = caps.schemas
            @audit_log = caps.audit_log
          end

          def call
            Validator.new(
              reader: Get::Impl.new(ctx: @ctx, caps: @caps),
              manifest: @manifest,
              audit_log: @audit_log,
              schema_for: ->(name) { @schemas.fetch_or_nil(name) },
            ).call
          end
        end
      end
    end
  end
end

Textus::Application::UseCase.register(:validate_all, Textus::Application::Reads::ValidateAll, caps: :read)
