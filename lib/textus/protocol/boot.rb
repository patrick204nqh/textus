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
          event_store: container.store.audit_log,
          file_system: container.store.file_system,
          layout: container.layout,
        )
        envelope.merge(
          "catalog" => Catalog.build,
          "agent_protocol" => Protocol.build(manifest),
          "schemas" => build_schemas(container.schemas),
        )
      end

      def self.build_schemas(registry)
        return [] unless registry

        registry.all.map do |s|
          h = { "name" => s.name, "required" => s.required, "optional" => s.optional }
          h["fields"] = s.fields unless s.fields.empty?
          h["evolution"] = s.evolution unless s.evolution.empty?
          h
        end
      end
    end
  end
end
