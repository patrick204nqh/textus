module Textus
  module UseCases
    module Read
      class RdepsEntry < Base
        handles Dispatch::Contracts::RdepsEntry
        needs :manifest, :link_graph

        def call
          source_rdeps = @manifest.data.entries.each_with_object([]) do |entry, acc|
            next unless entry.external?

            sources = Array(entry.source&.sources).compact
            acc << entry.key if sources.any? { |s| s == @command.key || @command.key.start_with?("#{s}.") }
          end

          link_rdeps = @link_graph.links_to(@command.key)
          rdeps      = (source_rdeps + link_rdeps).uniq.sort
          success("key" => @command.key, "rdeps" => rdeps)
        end
      end
    end
  end
end
