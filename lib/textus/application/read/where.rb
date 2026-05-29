module Textus
  module Application
    module Read
      class Where
        def initialize(container:, call: nil, hook_context: nil) # rubocop:disable Lint/UnusedMethodArgument
          @manifest = container.manifest
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

Textus::Application::UseCase.register(:where, Textus::Application::Read::Where, caps: :read)
