Textus.workflow "materialize" do
  handles "entry.written", "entry.deleted", "entry.moved",
          "proposal.accepted", "proposal.rejected"
  priority 10
  max_attempts 3

  step :converge do |data, ctx|
    registry = ctx.container.workflow_registry || Textus::Workflow::Registry.new(ctx.workflows)
    matched = registry.workflows_for_key(ctx.key)
    if matched.empty?
      entry = ctx.container.manifest.resolver.resolve(ctx.key).entry
      if entry.publish_tree || !Array(entry.publish_to).empty?
        es = Textus::Protocol::StoreEngine.new(
          file_system: ctx.container.store.file_system,
          manifest: ctx.container.manifest,
          layout: ctx.container.layout,
          store: ctx.container.store,
          schemas: ctx.container.schemas,
        )
        pctx = Textus::Protocol::Manifest::Entry::Base::PublishContext.new(
          container: ctx.container, call: ctx.call,
          reader: ->(key:) { es.read(key:) }
        )
        entry.publish_via(pctx)
      end
    end
    data
  end
end
