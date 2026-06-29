module Textus
  module Dispatch
    module Middleware
      class Cascade < Base
        middleware_name :cascade

        CASCADE_VERBS = %i[put propose accept reject key_mv key_delete].freeze

        TRIGGER_TYPE_MAP = {
          Contracts::PutEntry => "entry.written",
          Contracts::ProposeEntry => "entry.written",
          Contracts::DeleteKey => "entry.deleted",
          Contracts::MoveKey => "entry.moved",
          Contracts::AcceptProposal => "proposal.accepted",
          Contracts::RejectProposal => "proposal.rejected",
        }.freeze

        def call(container:, command:, call:, next_handler:)
          result = next_handler.call(command, call)
          return result unless result.success? && cascadable?(command)

          key = cascade_key(command)
          return result unless key

          trigger_type = TRIGGER_TYPE_MAP[command.class]
          jobs = Textus::Store::Jobs::Planner.new(container: container).plan(
            trigger: { "type" => trigger_type, "target" => key },
            role: call.role,
          )
          queue = Textus::Store::Jobs::Queue.new(store: container.job_store)
          jobs.each { |j| queue.enqueue(j) }
          result
        end

        private

        def cascadable?(command)
          CASCADE_VERBS.include?(VerbRegistry.contract_to_verb!(command.class).to_sym)
        end

        def cascade_key(command)
          case command
          when Contracts::PutEntry, Contracts::DeleteKey then command.key
          when Contracts::MoveKey                        then command.new_key
          when Contracts::AcceptProposal,
               Contracts::RejectProposal                 then command.pending_key
          when Contracts::ProposeEntry                   then command.key
          end
        end
      end
    end
  end
end
