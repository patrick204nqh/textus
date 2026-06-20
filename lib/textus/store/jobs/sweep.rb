module Textus
  class Store
    module Jobs
      class Sweep < Base
        REQUIRED_ROLE = Textus::Value::Role::AUTOMATION
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
            file_stat: Textus::Port::Storage::FileStat.new,
            clock: Textus::Port::Clock.new,
          ).call(prefix: prefix, lane: lane)
          Textus::Store::Jobs::Retention.new(container: container, call: call).call(rows)
        end
      end
    end
  end
end
