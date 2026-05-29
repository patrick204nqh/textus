module Textus
  module Application
    module Read
      class Stale
        def initialize(container:, call: nil, hook_context: nil) # rubocop:disable Lint/UnusedMethodArgument
          @manifest = container.manifest
        end

        def call(prefix: nil, zone: nil)
          Textus::Domain::Staleness.new(manifest: @manifest).call(prefix: prefix, zone: zone)
        end
      end
    end
  end
end

Textus::Application::UseCase.register(:stale, Textus::Application::Read::Stale, caps: :read)
