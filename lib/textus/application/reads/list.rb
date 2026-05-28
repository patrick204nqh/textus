module Textus
  module Application
    module Reads
      module List
        def self.call(*, session:, ctx:, caps:, **) # rubocop:disable Lint/UnusedMethodArgument
          Impl.new(caps: caps).call(*, **)
        end

        class Impl
          def initialize(caps:)
            @manifest = caps.manifest
          end

          def call(prefix: nil, zone: nil)
            rows = @manifest.resolver.enumerate(prefix: prefix)
            rows = rows.select { |r| r[:manifest_entry].zone == zone } if zone
            rows.map { |row| { "key" => row[:key], "zone" => row[:manifest_entry].zone, "path" => row[:path] } }
          end
        end
      end
    end
  end
end

Textus::Application::UseCase.register(:list, Textus::Application::Reads::List, caps: :read)
