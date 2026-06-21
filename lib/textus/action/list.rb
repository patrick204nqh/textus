# frozen_string_literal: true

module Textus
  module Action
    class List < Base
      extend Textus::Contract::DSL

      verb :list
      summary "List keys filtered by lane and/or prefix."
      surfaces :cli, :mcp
      arg :prefix, String,
          description: "restrict to keys starting with this dotted prefix, e.g. 'knowledge.runbooks'"
      arg :lane, String,
          description: "restrict to one lane by name (see `boot` lanes); combine with prefix to narrow further"
      view(:cli) { |rows| { "entries" => rows } }

      def self.call(container:, call: nil, prefix: nil, lane: nil) # rubocop:disable Lint/UnusedMethodArgument
        manifest = container.manifest
        rows = manifest.resolver.enumerate(prefix: prefix)
        rows = rows.select { |row| row[:manifest_entry].lane == lane } if lane
        rows.map { |row| { "key" => row[:key], "lane" => row[:manifest_entry].lane, "path" => row[:path] } }
      end

      def self.leaf_keys(container:, prefix: nil, lane: nil)
        call(container: container, prefix: prefix, lane: lane)
          .map { |row| row.is_a?(Hash) ? (row["key"] || row[:key]) : row }
      end
    end
  end
end
