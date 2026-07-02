# frozen_string_literal: true

module Textus
  module UseCases
    module Ops
      module DrainStore
        HANDLES = Dispatch::Contracts::DrainStore
        NEEDS = %i[event_store workflows manifest layout].freeze

        CONSUMER = Textus::Events::Consumer.new

        def self.call(_command, call, deps)
          workflow_registry = Textus::Workflow::Registry.new(deps.workflows)
          result = CONSUMER.drain(
            db: deps.event_store.db,
            registry: workflow_registry,
            container: deps,
            call: call,
          )
          Value::Result.success(
            "protocol" => Textus::PROTOCOL,
            "ok" => result[:failed].zero?,
            "completed" => result[:completed],
            "failed" => result[:failed],
          )
        end
      end
    end
  end
end
