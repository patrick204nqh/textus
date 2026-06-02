module Textus
  module Read
    class Where
      extend Textus::Contract::DSL

      verb     :where
      summary  "Resolve a key to its zone, owner, and path without reading the body."
      surfaces :cli, :ruby, :mcp
      arg :key, String, required: true, positional: true,
                        description: "dotted key to locate (returns zone, owner, path; does not read content)"

      def initialize(container:, call: nil) # rubocop:disable Lint/UnusedMethodArgument
        @manifest = container.manifest
      end

      def call(key)
        res = @manifest.resolver.resolve(key)
        mentry = res.entry
        path = res.path
        { "protocol" => PROTOCOL, "key" => key, "zone" => mentry.zone, "owner" => mentry.owner, "path" => path }
      end
    end
  end
end
