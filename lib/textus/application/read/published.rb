module Textus
  module Application
    module Read
      module Published
        def self.call(*, session:, ctx:, caps:, **) # rubocop:disable Lint/UnusedMethodArgument
          Impl.new(caps: caps).call(*, **)
        end

        class Impl
          def initialize(caps:)
            @manifest = caps.manifest
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
end

Textus::Application::UseCase.register(:published, Textus::Application::Read::Published, caps: :read)
