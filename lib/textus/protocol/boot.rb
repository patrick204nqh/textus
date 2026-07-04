require_relative "boot/catalog"
require_relative "boot/protocol"
require_relative "boot/context"

module Textus
  module Protocol
    module Boot
      PROTOCOL_ID = PROTOCOL
      CURATED_CLI_VERBS = Catalog::CURATED_CLI_VERBS

      def self.contract_summaries
        Textus::Protocol::VerbRegistry.registered.to_h { |s| [s.verb.to_s, s.summary] }
      end

      def self.build(container:)
        manifest = container.manifest
        envelope = Context.build(
          manifest:,
          event_store: container.store.event_store,
          file_system: container.store.file_system,
          layout: container.layout,
        )
        envelope.merge(
          "catalog" => Catalog.build,
          "agent_protocol" => Protocol.build(manifest),
        )
      end
    end
  end
end
