require_relative "boot/catalog"
require_relative "boot/protocol"
require_relative "boot/context"

module Textus
  module Boot
    PROTOCOL_ID = PROTOCOL

    def self.lane_label(_manifest, _kind, fallback)
      fallback
    end

    def self.build(container:)
      envelope = Context.build(
        manifest: container.governance.manifest,
        audit_log: container.logging.audit_log,
        file_system: container.storage.file_system,
        layout: container.storage.layout,
      )
      envelope.merge(
        "catalog" => Catalog.build,
        "protocol" => Protocol.build(container.governance.manifest),
      )
    end
  end
end
