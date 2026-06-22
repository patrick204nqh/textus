module Textus
  module Bus
    module Middleware
      class Cascade < Base
        middleware_name :cascade

        CASCADE_VERBS = %i[put propose accept reject key_mv key_delete].freeze

        def initialize(container)
          @container = container
          @manifest = container.manifest
          @job_store = container.job_store
        end

        def call(command, call, next_handler)
          result = next_handler.call(command)
          return result unless result.success? && cascadable?(command)

          key = cascade_key(command)
          return result unless key

          enqueue_dependents(key, call)
          result
        end

        private

        def cascadable?(command)
          CASCADE_VERBS.include?(verb_for(command.class))
        end

        def cascade_key(command)
          case command
          when Contracts::PutEntry, Contracts::DeleteKey then command.key
          when Contracts::MoveKey then command.new_key
          when Contracts::AcceptProposal, Contracts::RejectProposal then command.pending_key
          when Contracts::ProposeEntry then command.key
          else nil
          end
        end

        def enqueue_dependents(key, call)
          entries = @manifest.data.entries.select(&:external?)
          rdeps = entries.each_with_object([]) do |entry, acc|
            sources = Array(entry.source&.sources).compact
            acc << entry.key if sources.any? { |source| source == key || key.start_with?("#{source}.") }
          end
          producible = rdeps.select { |dep_key| producible?(dep_key) }
          producible.each do |dep_key|
            Textus::Store::Jobs::Materialize.call(container: @container, call: call, key: dep_key)
          end
        rescue StandardError
          nil
        end

        def producible?(key)
          entry = @manifest.resolver.resolve(key).entry
          !entry.publish_tree.nil?
        rescue Textus::Error
          false
        end

        CONTRACT_TO_VERB = {
          Contracts::PutEntry => :put, Contracts::DeleteKey => :key_delete,
          Contracts::MoveKey => :key_mv, Contracts::ProposeEntry => :propose,
          Contracts::AcceptProposal => :accept, Contracts::RejectProposal => :reject,
        }.freeze

        def verb_for(klass)
          CONTRACT_TO_VERB[klass] || klass.name.split("::").last.gsub(/([a-z])([A-Z])/, '\1_\2').downcase.to_sym
        end
      end
    end
  end
end
