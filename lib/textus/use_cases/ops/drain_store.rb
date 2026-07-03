# frozen_string_literal: true

module Textus
  module UseCases
    module Ops
      class DrainStore < Base
        handles Dispatch::Contracts::DrainStore
        needs :event_store, :workflows, :manifest, :layout

        CONSUMER = Textus::Events::Consumer.new

        def call
          workflow_registry = Textus::Workflow::Registry.new(workflows)
          result = CONSUMER.drain(
            event_store: event_store,
            registry: workflow_registry,
            container: self,
            call: @call,
          )
          success(
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
