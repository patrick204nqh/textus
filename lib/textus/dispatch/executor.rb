# frozen_string_literal: true

module Textus
  module Dispatch
    # Runs each declared action inline (:sync) or enqueues as a Job (:async).
    # For :async, if no watcher is running, actions remain queued for drain/watch.
    # Returns an Array of results - nil for async actions.
    class Executor
      def initialize(container)
        @container = container
      end

      def run(event)
        call_value = Textus::Call.build(
          role: event.actor || Textus::Role::AUTOMATION,
          correlation_id: event.correlation_id,
        )

        event.actions.map { |action| dispatch(action, call_value) }
      end

      private

      def dispatch(action, call_value)
        case action.class::BURN
        when :sync
          action.call(container: @container, call: call_value)
        when :async
          job = Textus::Core::Jobs::Job.new(
            type: action_type(action),
            args: action.args,
            enqueued_by: call_value.role,
            max_attempts: 3,
          )
          queue.enqueue(job)
          nil
        when :async_event
          job = Textus::Core::Jobs::Job.new(
            type: action_type(action),
            args: action.args,
            enqueued_by: call_value.role,
            max_attempts: 1,
          )
          queue.enqueue(job)
          nil
        else
          raise Textus::UsageError.new("unknown burn mode: #{action.class::BURN.inspect}")
        end
      end

      def action_type(action)
        return action.class.const_get(:TYPE) if action.class.const_defined?(:TYPE, false)

        name = action.class.name
        return name.gsub("::", "/").downcase if name

        "anonymous_action_#{action.class.object_id}"
      end

      def queue
        @queue ||= Textus::Ports::Queue.new(root: @container.root)
      end
    end
  end
end
