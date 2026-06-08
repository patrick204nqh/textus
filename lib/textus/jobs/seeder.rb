module Textus
  module Jobs
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

      def seed(prefix:, zone:)
        file_stat = Textus::Ports::Storage::FileStat.new

        producible_keys(prefix, zone).each do |key|
          @queue.enqueue(job("materialize", { "key" => key }, Textus::Role::AUTOMATION))
        end
        stale_intake_keys(prefix, zone, file_stat).each do |key|
          @queue.enqueue(job("re-pull", { "key" => key }, Textus::Role::AUTOMATION))
        end
        @queue.enqueue(job("sweep", { "scope" => { "prefix" => prefix, "zone" => zone } }, @call.role))
      end

      private

      def job(type, args, role)
        Textus::Domain::Jobs::Job.new(type: type, args: args, enqueued_by: role)
      end

      # Mirrors the converge scope (the publishable arm).
      def producible_keys(prefix, zone)
        @manifest.data.entries
                 .select { |e| e.derived? || !e.publish_tree.nil? || !e.publish_to.empty? }
                 .select { |e| in_scope?(e, prefix, zone) }
                 .map(&:key)
      end

      def stale_intake_keys(prefix, zone, file_stat)
        Textus::Domain::Freshness::Evaluator.new(
          manifest: @manifest, file_stat: file_stat, clock: Textus::Ports::Clock.new,
        ).stale_intake_keys(prefix: prefix, zone: zone)
      end

      def in_scope?(entry, prefix, zone)
        return false if zone && entry.zone != zone
        return false if prefix && !entry.key.start_with?(prefix)

        true
      end
    end
  end
end
