module Textus
  module Write
    class RefreshOrchestrator
      def initialize(worker:, store_root:, events:, call: nil, hook_context: nil, detached_spawner: nil)
        @worker       = worker
        @store_root   = store_root
        @events       = events
        @call         = call
        @hook_context = hook_context
        @detached_spawner = detached_spawner || default_spawner
      end

      def execute(action, key:)
        case action
        when Textus::Domain::Action::Return       then Textus::Domain::Outcome::Skipped.new
        when Textus::Domain::Action::RefreshSync  then run_sync(key)
        when Textus::Domain::Action::RefreshTimed then run_timed(action.budget_ms, key)
        else raise ArgumentError.new("unknown action: #{action.inspect}")
        end
      end

      private

      def run_sync(key)
        envelope = @worker.run(key)
        Textus::Domain::Outcome::Refreshed.new(envelope: envelope)
      rescue Textus::Error => e
        Textus::Domain::Outcome::Failed.new(error: e)
      end

      def run_timed(budget_ms, key)
        return run_timed_with_fork(budget_ms, key) if Textus::Ports::Refresh::Detached.supported?

        run_timed_cooperative(budget_ms, key)
      end

      def run_timed_cooperative(budget_ms, key)
        result = nil
        thread = Thread.new do
          result = @worker.run(key)
        rescue Textus::Error => e
          result = e
        end

        thread.join(budget_ms / 1000.0)
        if thread.alive?
          thread.kill
          return Textus::Domain::Outcome::Failed.new(
            error: Textus::UsageError.new(
              "refresh exceeded budget #{budget_ms}ms (no fork available — cooperative cancel)",
            ),
          )
        end

        if result.is_a?(Textus::Error)
          Textus::Domain::Outcome::Failed.new(error: result)
        else
          Textus::Domain::Outcome::Refreshed.new(envelope: result)
        end
      end

      def run_timed_with_fork(budget_ms, key)
        result = nil
        thread = Thread.new do
          result = @worker.run(key)
        rescue Textus::Error => e
          result = e
        end

        thread.join(budget_ms / 1000.0)

        if thread.alive?
          thread.kill

          # Single-flight: if a sibling process / earlier fork holds the
          # per-leaf lock, don't fork another worker — they're already
          # doing this work.
          probe = Textus::Ports::Refresh::Lock.new(root: @store_root, key: key)
          return Textus::Domain::Outcome::Detached.new unless probe.try_acquire

          probe.release

          payload = { key: key, started_at: Time.now.utc.iso8601, budget_ms: budget_ms }
          payload[:ctx] = @hook_context if @hook_context
          @events.publish(:refresh_backgrounded, **payload)
          @detached_spawner.call(store_root: @store_root, key: key)
          Textus::Domain::Outcome::Detached.new
        elsif result.is_a?(Textus::Error)
          Textus::Domain::Outcome::Failed.new(error: result)
        else
          Textus::Domain::Outcome::Refreshed.new(envelope: result)
        end
      end

      def default_spawner
        Textus::Ports::Refresh::Detached.method(:spawn)
      end
    end
  end
end
