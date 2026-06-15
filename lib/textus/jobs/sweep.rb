module Textus
  module Jobs
    class Sweep < Base
      REQUIRED_ROLE = Textus::Role::AUTOMATION
      TYPE = "sweep"

      def initialize(scope: nil, key: nil)
        super()
        @scope = scope || {}
        @key   = key
      end

      def args = { scope: @scope, key: @key }.compact

      def call(container:, call:)
        prefix = @key || (@scope.is_a?(Hash) ? @scope["prefix"] : nil)
        lane   = @scope.is_a?(Hash) ? @scope["lane"] : nil
        rows = Textus::Core::Retention::Sweep.new(
          manifest: container.manifest,
          file_stat: Textus::Ports::Storage::FileStat.new,
          clock: Textus::Ports::Clock.new,
        ).call(prefix: prefix, lane: lane)
        Textus::Jobs::Retention.new(container: container, call: call).call(rows)
      end
    end
  end
end
