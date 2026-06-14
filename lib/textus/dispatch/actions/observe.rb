# frozen_string_literal: true

module Textus
  module Dispatch
    module Actions
      # Fire-and-forget observe action. Handlers execute asynchronously
      # and are never retried.
      class Observe < Base
        TYPE = "observe"
        BURN = :async_event

        def initialize(event_name:, key:, envelope: nil)
          super()
          @event_name = event_name
          @key = key
          @envelope = envelope
        end

        def args = { event_name: @event_name, key: @key }

        def call(container:, call:)
          container.steps.publish(
            @event_name.to_sym,
            ctx: Textus::Step::Context.for(container: container, call: call),
            key: @key,
            envelope: @envelope,
          )
        end
      end
    end
  end
end
