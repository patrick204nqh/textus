# frozen_string_literal: true

module Textus
  module Action
    class Drain < Base
      extend Textus::Contract::DSL

      verb :drain
      summary "Seed refresh + sweep jobs then drain the queue to empty. " \
              "Identical to one Watcher tick. Use when no watcher is running."
      surfaces :cli, :mcp
      arg :prefix, String, description: "restrict to keys under this dotted prefix"
      arg :lane,   String, description: "restrict to entries in this lane"

      BURN = :sync

      def initialize(prefix: nil, lane: nil)
        super()
        @prefix = prefix
        @lane   = lane
      end

      def call(container:, call:)
        queue = Textus::Ports::Queue.new(root: container.root)
        Textus::Background::Planner::Plan.seed(
          container: container,
          queue: queue,
          role: call.role,
        )
        queue.reclaim(now: Textus::Ports::Clock.new.now)
        summary = Textus::Background::Worker.for(container:, queue:).drain
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
