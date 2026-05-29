module Textus
  module Read
    class Retainable
      def initialize(container:, call: nil) # rubocop:disable Lint/UnusedMethodArgument
        @manifest = container.manifest
      end

      def call(prefix: nil, zone: nil)
        Textus::Domain::Retention.new(
          manifest: @manifest,
          file_stat: Textus::Ports::Storage::FileStat.new,
          clock: Textus::Ports::Clock,
        ).call(prefix: prefix, zone: zone)
      end
    end
  end
end
