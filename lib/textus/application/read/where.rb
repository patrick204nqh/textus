module Textus
  module Application
    module Read
      module Where
        def self.call(*, session:, ctx:, caps:, **) # rubocop:disable Lint/UnusedMethodArgument
          Impl.new(caps: caps).call(*, **)
        end

        class Impl
          def initialize(caps:)
            @manifest = caps.manifest
          end

          def call(key)
            res = @manifest.resolver.resolve(key)
            mentry = res.entry
            path = res.path
            { "protocol" => PROTOCOL, "key" => key, "zone" => mentry.zone, "owner" => mentry.owner, "path" => path }
          end
        end
      end
    end
  end
end

Textus::Application::UseCase.register(:where, Textus::Application::Read::Where, caps: :read)
