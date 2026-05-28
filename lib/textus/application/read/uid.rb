module Textus
  module Application
    module Read
      module Uid
        def self.call(*, session:, ctx:, caps:, **) # rubocop:disable Lint/UnusedMethodArgument
          Impl.new(ctx: ctx, caps: caps).call(*, **)
        end

        class Impl
          def initialize(ctx:, caps:)
            @ctx = ctx
            @caps = caps
          end

          def call(key)
            get.get(key).uid
          end

          private

          def get
            @get ||= Get::Impl.new(ctx: @ctx, caps: @caps)
          end
        end
      end
    end
  end
end

Textus::Application::UseCase.register(:uid, Textus::Application::Read::Uid, caps: :read)
