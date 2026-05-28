module Textus
  module Application
    module Reads
      module Stale
        def self.call(*, session:, ctx:, caps:, **) # rubocop:disable Lint/UnusedMethodArgument
          Impl.new(caps: caps).call(*, **)
        end

        class Impl
          def initialize(caps:)
            @manifest = caps.manifest
          end

          def call(prefix: nil, zone: nil)
            Textus::Domain::Staleness.new(manifest: @manifest).call(prefix: prefix, zone: zone)
          end
        end
      end
    end
  end
end

Textus::Application::UseCase.register(:stale, Textus::Application::Reads::Stale, caps: :read)
