module Textus
  module Application
    module Read
      module Rdeps
        def self.call(*, session:, ctx:, caps:, **) # rubocop:disable Lint/UnusedMethodArgument
          Impl.new(caps: caps).call(*, **)
        end

        class Impl
          def initialize(caps:)
            @manifest = caps.manifest
          end

          def call(key)
            @manifest.data.entries.each_with_object([]) do |e, acc|
              next unless e.is_a?(Textus::Manifest::Entry::Derived)

              src = e.source
              sources = if src.is_a?(Textus::Manifest::Entry::Derived::Projection)
                          Array(src.select).compact
                        elsif src.is_a?(Textus::Manifest::Entry::Derived::External)
                          Array(src.sources).compact
                        else
                          []
                        end
              acc << e.key if sources.any? { |s| s == key || key.start_with?("#{s}.") }
            end
          end
        end
      end
    end
  end
end

Textus::Application::UseCase.register(:rdeps, Textus::Application::Read::Rdeps, caps: :read)
