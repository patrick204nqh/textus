module Textus
  module Produce
    # Single home for the fetch lifecycle event vocabulary (ADR 0048 D5).
    # Produce::Acquire::Intake (the ingest executor driven by converge + hook) emits through
    # this seam so the event names and payload shapes live in one place with one
    # derived hook context.
    class Events
      def self.from(container:, call:)
        new(
          steps: container.steps,
          hook_context: Textus::Step::Context.for(container: container, call: call),
        )
      end

      def initialize(steps:, hook_context:)
        @steps = steps
        @hook_context = hook_context
      end

      def started(key, mode: :sync)
        @steps.publish(:entry_fetch_started, ctx: @hook_context, key: key, mode: mode)
      end

      def failed(key, error)
        @steps.publish(:entry_fetch_failed, ctx: @hook_context, key: key,
                                            error_class: error.class.name, error_message: error.message)
      end

      def fetched(key, envelope, change)
        return if change == :unchanged

        @steps.publish(:entry_fetched, ctx: @hook_context, key: key, envelope: envelope, change: change)
      end
    end
  end
end
