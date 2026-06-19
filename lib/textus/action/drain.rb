# frozen_string_literal: true

module Textus
  module Action
    class Drain < Base
      extend Textus::Contract::DSL

      verb :drain
      summary "Seed materialize + sweep jobs then drain the queue to empty. " \
              "Identical to one Watcher tick. Use when no watcher is running."
      surfaces :cli, :mcp
      arg :prefix, String, description: "restrict to keys under this dotted prefix"
      arg :lane,   String, description: "restrict to entries in this lane"

      def initialize(prefix: nil, lane: nil)
        super()
        @prefix = prefix
        @lane   = lane
      end

      def call(container:, call:)
        store = Textus::Ports::Store.new(root: container.root).setup!
        queue = Textus::Jobs::Queue.new(store: store)
        Textus::Jobs::Planner.seed(
          container: container,
          queue: queue,
          role: call.role,
        )
        queue.reclaim(now: Textus::Ports::Clock.new.now)
        summary = Textus::Jobs::Worker.for(container:, queue:).drain
        {
          "protocol" => Textus::PROTOCOL,
          "ok" => summary.failed.zero?,
          "completed" => summary.completed,
          "failed" => summary.failed,
        }
      ensure
        store&.close
      end
    end
  end
end
