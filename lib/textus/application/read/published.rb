module Textus
  module Application
    module Read
      class Published
        def initialize(container:, call: nil, hook_context: nil) # rubocop:disable Lint/UnusedMethodArgument
          @manifest = container.manifest
        end

        def call
          @manifest.data.entries.reject { |e| e.publish_to.empty? }.map do |e|
            { "key" => e.key, "publish_to" => e.publish_to }
          end
        end
      end
    end
  end
end

Textus::Application::UseCase.register(:published, Textus::Application::Read::Published, caps: :read)
