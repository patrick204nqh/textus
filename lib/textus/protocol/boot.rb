require_relative "boot/catalog"
require_relative "boot/protocol"
require_relative "boot/context"

module Textus
  module Protocol
    module Boot
      # boot answers 5 questions for the agent:
      #   1. Where am I?       → contract (store_root, etag)
      #   2. What can I do?     → agent (verbs, writable lanes, propose lane, tips)
      #   3. What can't I do?   → plugin (protected_paths, protected_lanes, publish_targets)
      #   4. What's here?       → project (identity), state (loop, runbooks, entry_blueprints)
      #   5. How do I talk?     → agent.protocol (envelope_shape, roles, discipline)

      PROTOCOL_ID = PROTOCOL
      CURATED_CLI_VERBS = Catalog::CURATED_CLI_VERBS

      def self.contract_summaries
        Textus::Protocol::ActionRegistry.registered.to_h { |s| [s.action.to_s, s.summary] }
      end

      def self.build(container:)
        envelope = Context.build(
          manifest: container.manifest,
          event_store: container.store.audit_log,
          file_system: container.store.file_system,
          layout: container.layout,
        )
        envelope.merge(
          "catalog" => Catalog.build,
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
