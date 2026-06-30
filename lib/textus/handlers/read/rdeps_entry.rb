module Textus
  module Handlers
    module Read
      class RdepsEntry
        def initialize(manifest:, link_edge_store: Textus::Links::LinkEdgeStore.new)
          @manifest        = manifest
          @link_edge_store = link_edge_store
        end

        def call(command, _call)
          source_rdeps = @manifest.data.entries.each_with_object([]) do |entry, acc|
            next unless entry.external?

            sources = Array(entry.source&.sources).compact
            acc << entry.key if sources.any? { |s| s == command.key || command.key.start_with?("#{s}.") }
          end

          link_rdeps = @link_edge_store.dependents_of(command.key)
          rdeps      = (source_rdeps + link_rdeps).uniq.sort
          Value::Result.success("key" => command.key, "rdeps" => rdeps)
        end
      end
    end
  end
end
