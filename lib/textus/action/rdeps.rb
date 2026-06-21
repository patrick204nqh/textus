# frozen_string_literal: true

module Textus
  module Action
    class Rdeps < Base

      verb :rdeps
      summary "List the derived entries that depend on a key (reverse deps / impact set)."
      surfaces :cli, :mcp
      arg :key, String, required: true, positional: true,
                        description: "dotted key whose dependents (what would be stranded if it moved) you want"

      def self.call(container:, key:, **)
        manifest = container.manifest
        rdeps = manifest.data.entries.each_with_object([]) do |entry, acc|
          next unless entry.external?

          sources = Array(entry.source&.sources).compact
          acc << entry.key if sources.any? { |source| source == key || key.start_with?("#{source}.") }
        end
        { "key" => key, "rdeps" => rdeps }
      end
    end
  end
end
