module Textus
  module Bus
    module Middleware
      class Cascade < Base
        middleware_name :cascade

        CASCADE_VERBS = %i[put propose accept reject key_mv key_delete].freeze

        def call(container:, command:, call:, next_handler:)
          result = next_handler.call(command, call)
          return result unless result.success? && cascadable?(command)

          key = cascade_key(command)
          return result unless key

          enqueue_dependents(key, call, container)
          result
        end

        private

        def cascadable?(command)
          CASCADE_VERBS.include?(Bus.contract_to_verb!(command.class).to_sym)
        end

        def cascade_key(command)
          case command
          when Contracts::PutEntry, Contracts::DeleteKey then command.key
          when Contracts::MoveKey then command.new_key
          when Contracts::AcceptProposal, Contracts::RejectProposal then command.pending_key
          when Contracts::ProposeEntry then command.key
          end
        end

        def enqueue_dependents(key, call, container)
          manifest = container.manifest
          entries = manifest.data.entries.select(&:external?)
          rdeps = entries.each_with_object([]) do |entry, acc|
            sources = Array(entry.source&.sources).compact
            acc << entry.key if sources.any? { |source| source == key || key.start_with?("#{source}.") }
          end
          producible = rdeps.select { |dep_key| producible?(dep_key, manifest) }
          producible.each do |dep_key|
            Textus::Store::Jobs::Materialize.call(container: container, call: call, key: dep_key)
          end
        rescue StandardError
          nil
        end

        def producible?(key, manifest)
          entry = manifest.resolver.resolve(key).entry
          !entry.publish_tree.nil?
        rescue Textus::Error
          false
        end
      end
    end
  end
end
