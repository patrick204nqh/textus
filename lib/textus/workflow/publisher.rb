module Textus
  module Workflow
    class Publisher
      def initialize(container:, call:)
        @container = container
        @call      = call
      end

      def publish(key, data, ctx, definition)
        definition.publish_targets.each { |t| publish_one(key, data, ctx, target: t) }

        if definition.save_key
          write_to_key(definition.save_key, data, ctx)
        end

        definition.notify_keys.each { |nk| notify_key(nk, ctx) }

        definition.publish_block&.call(data, ctx)
      end

      private

      def write_to_key(target_key, data, ctx)
        res = @container.manifest.resolver.resolve(target_key)
        es = Protocol::EntryStore.new(
          file_system: @container.store.file_system,
          manifest: @container.manifest,
          layout: @container.layout,
          store: @container.store,
          workflow_registry: @container.workflow_registry,
        )
        normalized = Textus::Protocol::Format.data_to_payload(data, res.entry.format)
        payload = Textus::Value::Payload.new(**normalized)
        es.put(target_key, mentry: res.entry, payload:, call: @call)
      end

      def notify_key(target_key, ctx)
        res = @container.manifest.resolver.resolve(target_key)
        es = Protocol::EntryStore.new(
          file_system: @container.store.file_system,
          manifest: @container.manifest,
          layout: @container.layout,
          store: @container.store,
          workflow_registry: @container.workflow_registry,
        )
        payload = Textus::Value::Payload.new(meta: {}, body: nil, content: {})
        es.put(target_key, mentry: res.entry, payload:, call: @call)
      end

      def write_and_pctx(key, data, ctx)
        normalized = Textus::Protocol::Format.data_to_payload(data, ctx.entry.format)
        payload = Textus::Value::Payload.new(**normalized)
        es = Protocol::EntryStore.new(
          file_system: @container.store.file_system,
          manifest: @container.manifest,
          layout: @container.layout,
          store: @container.store,
          workflow_registry: @container.workflow_registry,
        )
        es.put(key, mentry: ctx.entry, payload:, call: @call)
        Textus::Protocol::Manifest::Entry::Base::PublishContext.new(
          container: @container,
          reader: es.method(:read)
        )
      end

      def publish_one(key, data, ctx, target:)
        pctx = write_and_pctx(key, data, ctx)
        attrs = { "to" => target.to, "template" => target.template,
                  "tree" => target.tree }
        attrs["inject_boot"] = true if target.inject_boot
        pub_target = Textus::Protocol::Manifest::Policy::PublishTarget.new(attrs)
        entry = ctx.entry.with_publish_targets([pub_target])
        entry.publish_via(pctx)
      end
    end
  end
end
