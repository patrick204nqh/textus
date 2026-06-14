module Textus
  module Dispatch
    module Planner
      # Enqueues the full convergence set for a scope: a produce job per derived /
      # publish_tree / publish.to entry, a re-pull job per stale intake key, and a
      # single sweep job for the scope. The scope logic mirrors
      # the converge scope (Produce::Engine) so `drain` and `serve` converge identically.
      # Produce jobs self-elevate (stamped automation); the sweep job carries the
      # caller's role (destructive runs as caller).
      class Seeder
        def initialize(container:, queue:, call:)
          @container = container
          @queue = queue
          @call = call
          @manifest = container.manifest
        end

        def seed(prefix:, lane:)
          planner = Textus::Dispatch::Planner::Planner.new(container: @container)
          jobs = planner.plan(
            triggers: [{ "type" => "manual.kick" }],
            scope: { "prefix" => prefix, "lane" => lane },
            role: @call.role,
          )
          jobs.each { |j| @queue.enqueue(j) }
        end
      end
    end
  end
end
