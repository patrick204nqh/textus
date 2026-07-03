require_relative "boot/catalog"
require_relative "boot/protocol"
require_relative "boot/context"

module Textus
  module Protocol
    module Boot
      PROTOCOL_ID = PROTOCOL
      CURATED_CLI_VERBS = Catalog::CURATED_CLI_VERBS

      def self.contract_summaries
        Textus::VerbRegistry.registered.to_h { |s| [s.verb.to_s, s.summary] }
      end

      def self.lane_label(_manifest, _kind, fallback)
        fallback
      end

      def self.build(container:)
        manifest = container.governance.manifest
        envelope = Context.build(
          manifest:,
          audit_log: container.logging.audit_log,
          file_system: container.storage.file_system,
          layout: container.storage.layout,
        )
        envelope.merge(
          "catalog" => Catalog.build,
          "agent_protocol" => Protocol.build(manifest),
        )
      end
    end
  end
end
