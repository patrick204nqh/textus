# frozen_string_literal: true

module Textus
  module Action
    class Drain < Base

      verb :drain
      summary "Seed materialize + sweep jobs then drain the queue to empty. " \
              "Identical to one Watcher tick. Use when no watcher is running."
      surfaces :cli, :mcp
      arg :prefix, String, description: "restrict to keys under this dotted prefix"
      arg :lane,   String, description: "restrict to entries in this lane"

      def self.call(container:, call:, prefix: nil, lane: nil) # rubocop:disable Lint/UnusedMethodArgument
        queue = Textus::Store::Jobs::Queue.new(store: container.job_store)
        Textus::Store::Jobs::Planner.seed(
          container: container,
          queue: queue,
          role: call.role,
        )
        queue.reclaim(now: Textus::Port::Clock.new.now)
        summary = Textus::Store::Jobs::Worker.for(container:, queue:).drain
        {
          "protocol" => Textus::PROTOCOL,
          "ok" => summary.failed.zero?,
          "completed" => summary.completed,
          "failed" => summary.failed,
        }
      end
    end
  end
end
