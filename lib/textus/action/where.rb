# frozen_string_literal: true

module Textus
  module Action
    class Where < Base
      verb :where
      summary "Resolve a key to its zone, owner, and path without reading the body."
      surfaces :cli, :mcp
      arg :key, String, required: true, positional: true,
                        description: "dotted key to locate (returns zone, owner, path; does not read content)"

      def self.call(container:, key:, call: nil) # rubocop:disable Lint/UnusedMethodArgument
        manifest = container.manifest
        res = manifest.resolver.resolve(key)
        mentry = res.entry
        path = res.path
        { "protocol" => Textus::PROTOCOL, "key" => key, "lane" => mentry.lane, "owner" => mentry.owner, "path" => path }
      end
    end
  end
end
