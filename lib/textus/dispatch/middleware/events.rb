module Textus
  module Dispatch
    module Middleware
      class Events < Base
        EVENT_MAP = {
          Contracts::PutEntry => "entry.written",
          Contracts::DeleteKey => "entry.deleted",
          Contracts::MvKey => "entry.moved",
          Contracts::ProposeEntry => "entry.written",
          Contracts::AcceptProposal => "proposal.accepted",
          Contracts::RejectProposal => "entry.deleted",
        }.freeze

        middleware_name :events

        def call(container:, command:, call:, next_handler:)
          result = next_handler.call(command, call)
          event_type = EVENT_MAP[command.class]
          return result unless event_type && result.success?

          key = key_for(command)
          registry  = Workflow::Registry.new(container.events.workflows)
          emitter   = Produce::EventEmitter.new(
            database: container.events.event_store.connection,
            workflow_registry: registry,
          )
          emitter.emit(event_type:, key:)
          result
        end

        private

        def key_for(command)
          if command.respond_to?(:key) then command.key
          elsif command.respond_to?(:old_key) then command.old_key
          elsif command.respond_to?(:pending_key) then command.pending_key
          end
        end
      end
    end
  end
end
