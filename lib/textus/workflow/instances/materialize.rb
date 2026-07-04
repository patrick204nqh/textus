# frozen_string_literal: true

module Textus
  module Workflow
    module Instances
      Materialize = Textus::Workflow::DSL::Definition.new("materialize").tap do |wf|
        wf.handles "entry.written", "entry.deleted", "entry.moved",
                   "proposal.accepted", "proposal.rejected"
        wf.priority 10
        wf.max_attempts 3
wf.step :converge do |data, ctx|
  registry = ctx.container.workflow_registry || Textus::Workflow::Registry.new(ctx.workflows)
  workflows = registry.workflows_for_key(ctx.key)
  if workflows.any?
    workflows.each { |wf| Textus::Workflow::Runner.new(wf, container: ctx.container, call: ctx.call).run(ctx.key) }
  else
    entry = ctx.container.manifest.resolver.resolve(ctx.key).entry
    if entry.publish_tree || !Array(entry.publish_to).empty?
      es = Textus::Protocol::EntryStore.new(
        file_system: ctx.container.store.file_system,
        manifest: ctx.container.manifest,
        layout: ctx.container.layout,
        store: ctx.container.store,
      )
      pctx = Textus::Protocol::Manifest::Entry::Base::PublishContext.new(
        container: ctx.container, call: ctx.call,
        reader: es.method(:read),
      )
      entry.publish_via(pctx)
    end
  end
  data
end
      end
    end
  end
end
