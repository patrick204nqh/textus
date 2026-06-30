module Textus
  module Handlers
    module Read
      module RdepsEntry
        HANDLES = Dispatch::Contracts::RdepsEntry
        NEEDS   = %i[manifest link_edge_store].freeze

        def self.call(command, _call, deps)
          source_rdeps = deps.manifest.data.entries.each_with_object([]) do |entry, acc|
            next unless entry.external?

            sources = Array(entry.source&.sources).compact
            acc << entry.key if sources.any? { |s| s == command.key || command.key.start_with?("#{s}.") }
          end

          link_rdeps = deps.link_edge_store.dependents_of(command.key)
          rdeps      = (source_rdeps + link_rdeps).uniq.sort
          Value::Result.success("key" => command.key, "rdeps" => rdeps)
        end
      end
    end
  end
end
