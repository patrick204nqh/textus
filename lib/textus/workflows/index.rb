# frozen_string_literal: true

module Textus
  module Workflows
    Index = Textus::Workflow::DSL::Definition.new("index").tap do |wf|
      wf.handles "entry.written", "entry.deleted"
      wf.priority 5
      wf.max_attempts 3
      wf.step :index_entry do |_data, ctx|
        key = ctx.key
        container = ctx.container
        entry = container.manifest.resolver.resolve(key).entry
        path = container.manifest.resolver.resolve(key).path
        db = container.event_store.db

        if container.file_system.exists?(path)
          body = container.file_system.read(path)
          db[:entries].insert_ignore.insert(
            key: key,
            lane: entry.lane,
            format: entry.format,
            content: body,
            indexed_at: Time.now.utc,
          )
        end
        nil
      end
    end
  end
end
