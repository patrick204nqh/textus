# frozen_string_literal: true

module Textus
  module Ports
    # ADR 0093 / job-queue model: on a canon write, enqueue a `materialize` job
    # for each derived entry that depends on the written key (rdeps ∩ producible).
    # Async-only — the write returns immediately; a worker (drain/serve) converges
    # the jobs. There is no inline `sync` path and no in-process thread: freshness
    # is re-homed to drain (at the commit/CI gate) and the daemon. A write INTO a
    # derived entry does not fan out (recursion guard). Produce self-elevates, so
    # the job is stamped automation. Attached at Store boot, alongside
    # AuditSubscriber.
    class ProduceOnWriteSubscriber
      def initialize(container)
        @container = container
      end

      def attach(registry)
        registry.on(:entry_written, :produce_on_write) do |key:, **|
          on_write(key: key)
        end
        # Closes the ADR 0087 gap: a delete/rename of a source must re-materialize
        # its orphaned dependents too, not just a write. These fire distinct
        # events (:entry_deleted / :entry_renamed), so subscribe to each.
        registry.on(:entry_deleted, :produce_on_delete) do |key:, **|
          on_write(key: key)
        end
        registry.on(:entry_renamed, :produce_on_rename) do |from_key:, to_key:, **|
          on_write(key: from_key)
          on_write(key: to_key)
        end
        self
      end

      def on_write(key:)
        return if derived_write?(key) # recursion guard: produce output is not a source change

        affected = Textus::Read::Rdeps.new(container: @container).call(key)["rdeps"]
        producible = affected.select { |k| producible?(k) }
        return if producible.empty?

        queue = Textus::Ports::Queue.new(root: @container.root)
        producible.each do |k|
          queue.enqueue(
            Textus::Domain::Jobs::Job.new(
              type: "materialize", args: { "key" => k }, enqueued_by: Textus::Role::AUTOMATION,
            ),
          )
        end
      end

      private

      def derived_write?(key)
        @container.manifest.resolver.resolve(key).entry.derived?
      rescue Textus::Error
        false
      end

      # The producible scope mirrors Produce::Engine#produce_one: derived
      # entries render+publish, and nested publish_tree entries mirror their
      # source subtree (ADR 0047). Including the latter restores reactive
      # re-mirroring on a write into a tree's source — dropped when the scope
      # narrowed to `derived?` only.
      def producible?(key)
        entry = @container.manifest.resolver.resolve(key).entry
        entry.derived? || !entry.publish_tree.nil?
      rescue Textus::Error
        false
      end
    end
  end
end
