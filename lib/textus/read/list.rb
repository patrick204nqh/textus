module Textus
  module Read
    class List
      extend Textus::Contract::DSL

      verb     :list
      summary  "List keys filtered by lane and/or prefix."
      surfaces :cli, :mcp
      arg :prefix, String, description: "restrict to keys starting with this dotted prefix, e.g. 'knowledge.runbooks'"
      arg :lane,   String, description: "restrict to one lane by name (see `boot` lanes); combine with prefix to narrow further"
      view(:cli) { |rows| { "entries" => rows } }

      def initialize(container:, call: nil) # rubocop:disable Lint/UnusedMethodArgument
        @manifest = container.manifest
      end

      def call(prefix: nil, lane: nil)
        rows = @manifest.resolver.enumerate(prefix: prefix)
        rows = rows.select { |r| r[:manifest_entry].lane == lane } if lane
        rows.map { |row| { "key" => row[:key], "lane" => row[:manifest_entry].lane, "path" => row[:path] } }
      end
    end
  end
end
