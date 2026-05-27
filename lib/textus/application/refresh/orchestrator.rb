module Textus
  module Application
    module Refresh
      class Orchestrator
        def initialize(worker:, store_root:, store: nil, role: "human", detached_spawner: nil)
          @worker = worker
          @store_root = store_root
          @store = store
          @role = role
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
          unless Textus::Infra::Refresh::Detached.supported?
            return Textus::Domain::Outcome::Failed.new(
              error: Textus::UsageError.new("timed_sync requires fork (Unix only)"),
            )
          end

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
            probe = Textus::Infra::Refresh::Lock.new(root: @store_root, key: key)
            return Textus::Domain::Outcome::Detached.new unless probe.try_acquire

            probe.release

            store_view = @store ? Textus::Application::Context.legacy(store: @store, role: @role) : nil
            payload = { key: key, started_at: Time.now.utc.iso8601, budget_ms: budget_ms }
            payload[:store] = store_view if store_view
            @store&.bus&.publish(:refresh_backgrounded, **payload)
            @detached_spawner.call(store_root: @store_root, key: key)
            Textus::Domain::Outcome::Detached.new
          elsif result.is_a?(Textus::Error)
            Textus::Domain::Outcome::Failed.new(error: result)
          else
            Textus::Domain::Outcome::Refreshed.new(envelope: result)
          end
        end

        def default_spawner
          Textus::Infra::Refresh::Detached.method(:spawn)
        end
      end
    end
  end
end
