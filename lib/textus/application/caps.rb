module Textus
  module Application
    # Capability records: role-scoped slices of the Store handed to use cases.
    # Zeitwerk maps this file to Textus::Application::Caps; the three
    # concrete cap types are also promoted to the Application namespace for
    # concise reference (Application::ReadCaps, etc.).
    module Caps
      ReadCaps = Data.define(:manifest, :file_store, :schemas, :root, :audit_log, :events)

      WriteCaps = Data.define(
        :manifest, :file_store, :schemas, :root,
        :audit_log, :events, :authorizer
      ) do
        def read
          ReadCaps.new(
            manifest: manifest, file_store: file_store, schemas: schemas, root: root,
            audit_log: audit_log, events: events
          )
        end
      end

      HookCaps = Data.define(:events, :rpc, :manifest, :root)
    end

    # Promote to Application namespace for concise reference.
    ReadCaps  = Caps::ReadCaps
    WriteCaps = Caps::WriteCaps
    HookCaps  = Caps::HookCaps

    def self.caps_from_store(store)
      read = ReadCaps.new(
        manifest: store.manifest, file_store: store.file_store,
        schemas: store.schemas, root: store.root,
        audit_log: store.audit_log, events: store.events
      )
      write = WriteCaps.new(
        manifest: store.manifest, file_store: store.file_store,
        schemas: store.schemas, root: store.root,
        audit_log: store.audit_log, events: store.events,
        authorizer: Textus::Domain::Authorizer.new(manifest: store.manifest)
      )
      hook = HookCaps.new(
        events: store.events, rpc: store.rpc,
        manifest: store.manifest, root: store.root
      )
      [read, write, hook]
    end
  end
end
