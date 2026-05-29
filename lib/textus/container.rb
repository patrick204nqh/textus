module Textus
  # Single capability record handed to every use case. Replaces the
  # ReadCaps/WriteCaps/HookCaps trio from 0.26.x. Built once per Store.
  Container = Data.define(
    :manifest, :file_store, :schemas, :root,
    :audit_log, :events, :rpc, :authorizer
  )

  class Container
    def self.from_store(store)
      new(
        manifest: store.manifest,
        file_store: store.file_store,
        schemas: store.schemas,
        root: store.root,
        audit_log: store.audit_log,
        events: store.events,
        rpc: store.rpc,
        authorizer: Textus::Domain::Authorizer.new(manifest: store.manifest),
      )
    end
  end
end
