require "securerandom"

module Textus
  module Surface
    class Watcher
      def initialize(container:)
        @container = container
        @async = Protocol::Async::Queue.new(container.store.event_store)
      end

      def tick
        loop do
          row = @async.consume_pending
          break unless row

          result = run_workflow(row)
          if result
            @async.mark_done(event_id: row[:id])
          else
            @async.mark_failed(event_id: row[:id], retry_count: row[:retry_count] || 0, error: "failed")
          end
        end
      end

      def run(poll: nil)
        interval = poll || @container.manifest.data.worker_config[:poll] || 2
        lock = Infra::Locks::WatcherLock.new(@container.root)
        lock.acquire
        begin
          loop do
            tick
            sleep(interval)
          end
        ensure
          lock.release
        end
      end

      private

      def run_workflow(row)
        Textus::Workflow::Runner.new(
          Textus::Workflow::Registry.new(@container.workflows).for(row[:workflow_type]),
          container: @container,
          call: Textus::Value::Call.build(role: Textus::Value::Role::AUTOMATION, correlation_id: SecureRandom.uuid),
        ).run(row[:key])
        true
      rescue Textus::Error => e
        warn "textus: watcher workflow #{row[:workflow_type]} failed: #{e.message}"
        false
      end
    end
  end
end
