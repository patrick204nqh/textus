module Textus
  module Application
    module Refresh
      class Orchestrator
        def initialize(worker:, bus:, store_root:, detached_spawner: nil)
          @worker = worker
          @bus = bus
          @store_root = store_root
          @detached_spawner = detached_spawner || default_spawner
        end

        def execute(action, key:, as:)
          case action
          when Textus::Domain::Action::Return       then Textus::Domain::Outcome::Skipped.new
          when Textus::Domain::Action::RefreshSync  then run_sync(key, as)
          when Textus::Domain::Action::RefreshTimed then run_timed(action.budget_ms, key, as)
          else raise ArgumentError.new("unknown action: #{action.inspect}")
          end
        end

        private

        def run_sync(key, as)
          envelope = @worker.run(key, as: as)
          Textus::Domain::Outcome::Refreshed.new(envelope: envelope)
        rescue Textus::Error => e
          Textus::Domain::Outcome::Failed.new(error: e)
        end

        def run_timed(budget_ms, key, as)
          unless Textus::Refresh::Detached.supported?
            return Textus::Domain::Outcome::Failed.new(
              error: Textus::UsageError.new("timed_sync requires fork (Unix only)"),
            )
          end

          result = nil
          thread = Thread.new do
            result = @worker.run(key, as: as)
          rescue Textus::Error => e
            result = e
          end

          thread.join(budget_ms / 1000.0)

          if thread.alive?
            thread.kill
            @bus.publish(:refresh_detached, key: key,
                                            started_at: Time.now.utc.iso8601,
                                            budget_ms: budget_ms)
            @detached_spawner.call(store_root: @store_root, key: key)
            Textus::Domain::Outcome::Detached.new
          elsif result.is_a?(Textus::Error)
            Textus::Domain::Outcome::Failed.new(error: result)
          else
            Textus::Domain::Outcome::Refreshed.new(envelope: result)
          end
        end

        def default_spawner
          Textus::Refresh::Detached.method(:spawn)
        end
      end
    end
  end
end
