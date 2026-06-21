# frozen_string_literal: true

module Textus
  module Action
    class Deps < Base
      extend Textus::Contract::DSL

      verb :deps
      summary "List the keys a derived entry depends on (its projection/external sources)."
      surfaces :cli, :mcp
      arg :key, String, required: true, positional: true,
                        description: "dotted key of the derived entry whose source keys you want"

      def self.call(container:, key:, **)
        entry = container.manifest.data.entries.find { |e| e.key == key }
        deps = entry&.external? ? Array(entry.source&.sources).compact : []
        { "key" => key, "deps" => deps.uniq }
      end
    end
  end
end
