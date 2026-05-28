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
    # aliases of the same `Hooks::Bus` object today, but they're carried as
    # separate fields against the ADR 0019 split of `Hooks::Bus` into two
    # narrower classes. Collapsing them back into one field would re-couple
    # callers to today's accident and un-do that forward compat.
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
