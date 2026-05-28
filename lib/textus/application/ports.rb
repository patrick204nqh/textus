module Textus
  module Application
    # Bundles the seven adapter handles that application use cases need from
    # a Store: the manifest (read-only domain config), the file_store (bytes
    # in and out), the schema registry, the audit log, the event bus
    # (pubsub) and rpc registry (rpc dispatch — same object today), and the
    # store root path on disk.
    #
    # Construct via `Ports.from_store(store)` at the Operations layer; from
    # there, every use case takes a single `ports:` kwarg and pulls only
    # the slice it needs into local ivars.
    Ports = Data.define(
      :manifest, :file_store, :schemas, :audit_log,
      :event_bus, :rpc_registry, :root
    ) do
      def self.from_store(store)
        new(
          manifest: store.manifest,
          file_store: store.file_store,
          schemas: store.schemas,
          audit_log: store.audit_log,
          event_bus: store.bus,
          rpc_registry: store.bus,
          root: store.root,
        )
      end
    end
  end
end
