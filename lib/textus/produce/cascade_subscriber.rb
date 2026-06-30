module Textus
  module Produce
    class CascadeSubscriber
      def initialize(manifest:, workflows:, job_store:, file_store:)
        @manifest   = manifest
        @workflows  = workflows
        @job_store  = job_store
        @file_store = file_store
      end

      def on_entry_written(event)
        trigger_cascade("entry.written", event.key, event.role)
      end

      def on_entry_deleted(event)
        trigger_cascade("entry.deleted", event.key, event.role)
      end

      def on_entry_moved(event)
        trigger_cascade("entry.moved", event.to_key, event.role)
      end

      def on_proposal_accepted(event)
        trigger_cascade("proposal.accepted", event.target_key, event.role)
      end

      def on_proposal_rejected(event)
        trigger_cascade("proposal.rejected", event.proposal_key, event.role)
      end

      private

      def trigger_cascade(trigger_type, key, role)
        container = build_container_proxy
        jobs = Textus::Store::Jobs::Planner.new(container: container).plan(
          trigger: { "type" => trigger_type, "target" => key },
          role: role,
        )
        queue = Textus::Store::Jobs::Queue.new(store: @job_store)
        jobs.each { |j| queue.enqueue(j) }
      end

      ContainerProxy = Data.define(:manifest, :workflows, :job_store, :file_store)

      def build_container_proxy
        ContainerProxy.new(
          manifest: @manifest, workflows: @workflows,
          job_store: @job_store, file_store: @file_store,
        )
      end
    end
  end
end
