module Textus
  module Application
    module Read
      class Deps
        def initialize(container:, call: nil, hook_context: nil) # rubocop:disable Lint/UnusedMethodArgument
          @manifest = container.manifest
        end

        def call(key)
          entry = @manifest.data.entries.find { |e| e.key == key } or return []
          return [] unless entry.is_a?(Textus::Manifest::Entry::Derived)

          src = entry.source
          result = if src.is_a?(Textus::Manifest::Entry::Derived::Projection)
                     Array(src.select).compact
                   elsif src.is_a?(Textus::Manifest::Entry::Derived::External)
                     Array(src.sources).compact
                   else
                     []
                   end
          result.uniq
        end
      end
    end
  end
end

Textus::Application::UseCase.register(:deps, Textus::Application::Read::Deps, caps: :read)
