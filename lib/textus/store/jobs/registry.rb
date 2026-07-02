module Textus
  class Store
    module Jobs
      module Registry
        class UnknownJob < KeyError; end

        JOBS = {
          "index" => ->(container:, call:, **) {
            Textus::Store::Index::Builder.new(store: container.job_store)
              .rebuild!(resolver: container.manifest.resolver)
          },
          "materialize" => ->(container:, call:, key:, **) {
            Textus::Produce::Engine.converge(container: container, call: call, keys: [key])
          },
          "sweep" => ->(container:, call:, scope: {}, key: nil, **) {
            rows = Retention::Sweep.new(
              manifest: container.manifest,
              workflows: container.workflows,
              file_stat: Textus::Port::Storage::FileStat.new,
              clock: Textus::Port::Clock.new,
            ).call(prefix: key || (scope.is_a?(Hash) ? scope["prefix"] : nil),
                   lane: scope.is_a?(Hash) ? scope["lane"] : nil)
            Retention::Base.new(container: container, call: call).call(rows)
          },
        }.freeze

        REQUIRED_ROLES = {
          "sweep" => Textus::Value::Role::AUTOMATION,
        }.freeze

        def self.fetch(type)
          JOBS.fetch(type.to_s) { raise UnknownJob.new("Unknown job type: #{type}") }
        end

        def self.required_role(type)
          REQUIRED_ROLES[type.to_s]
        end
      end
    end
  end
end
