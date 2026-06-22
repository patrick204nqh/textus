module Textus
  class Store
    module Jobs
      class Sweep < Base
        REQUIRED_ROLE = Textus::Value::Role::AUTOMATION
        TYPE = "sweep"

        def self.call(container:, call:, scope: {}, key: nil)
          prefix = key || (scope.is_a?(Hash) ? scope["prefix"] : nil)
          lane   = scope.is_a?(Hash) ? scope["lane"] : nil
          rows = Retention::Sweep.new(
            manifest: container.manifest,
            file_stat: Textus::Port::Storage::FileStat.new,
            clock: Textus::Port::Clock.new,
          ).call(prefix: prefix, lane: lane)
          Retention::Base.new(container: container, call: call).call(rows)
        end
      end
    end
  end
end
