module Textus
  module Application
    # Bundles the six adapter handles application use cases need from a
    # Store — manifest (read-only domain config), file_store (bytes in and
    # out), schemas (schema registry), audit_log, event_bus (pubsub),
    # rpc_registry (rpc dispatch) — plus the store root path on disk.
    #
    # Construct via `Ports.from_store(store)` at the Operations layer; from
    # there, every use case takes a single `ports:` kwarg and pulls only
    # the slice it needs into local ivars.
    #
    # WHY two fields for one object: `event_bus` and `rpc_registry` are
    # `event_bus` and `rpc_registry` are now separate objects after ADR 0019
    # split of `Hooks::Bus` into `Hooks::EventBus` and `Hooks::RpcRegistry`.
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
          event_bus: store.events,
          rpc_registry: store.rpc,
          root: store.root,
        )
      end
    end
  end
end
