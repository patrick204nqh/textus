module Textus
  module Workflow
    class Scheduler
      def initialize(registry:, workflow_queue:, reader:)
        @registry = registry
        @workflow_queue = workflow_queue
        @reader = reader
      end

      def seed_expired
        seeded = 0
        @registry.definitions.each do |wf|
          next unless wf.ttl && wf.save_to

          lane = wf.save_to.split(".").first
          next if @workflow_queue.pending?(event_type: "workflow", key: wf.save_to)

          entry = @reader.call(key: wf.save_to)
          unless entry
            @workflow_queue.push(
              event_type: "workflow", workflow_type: wf.type,
              key: wf.save_to, lane: lane,
            )
            seeded += 1
            next
          end

          meta = entry.respond_to?(:meta) ? entry.meta : (entry["_meta"] || {})
          generated_at = meta["generated_at"]
          next unless generated_at

          age = Time.now - Time.parse(generated_at)
          next unless age > wf.ttl

          @workflow_queue.push(
            event_type: "workflow", workflow_type: wf.type,
            key: wf.save_to, lane: lane,
          )
          seeded += 1
        end
        seeded
      end
    end
  end
end
