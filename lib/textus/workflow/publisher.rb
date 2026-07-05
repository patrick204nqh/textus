module Textus
  module Workflow
    class Publisher
      def initialize(container:, call:)
        @container = container
        @call      = call
        @store_engine = Protocol::StoreEngine.new(
          file_system: container.store.file_system,
          manifest: container.manifest,
          layout: container.layout,
          store: container.store,
          schemas: container.schemas,
        )
      end

      def publish(key, data, ctx, definition)
        definition.publish_targets.each { |t| publish_one(key, data, ctx, target: t) }

        write_to_key(definition.save_to, data, ctx) if definition.save_to

        definition.notify_keys.each { |nk| notify_key(nk, ctx) }

        definition.publish_block&.call(data, ctx)
      end

      private

      def write_to_key(target_key, data, ctx) # rubocop:disable Lint/UnusedMethodArgument
        res = @container.manifest.resolver.resolve(target_key)
        normalized = Textus::Protocol::Format.data_to_payload(data, res.entry.format)
        meta = stamped_meta(normalized[:meta])
        @store_engine.put(key: target_key, meta:, body: normalized[:body], content: normalized[:content], call: @call)
      end

      def notify_key(target_key, ctx) # rubocop:disable Lint/UnusedMethodArgument
        @store_engine.put(key: target_key, meta: {}, body: nil, content: {}, call: @call)
      end

      def write_and_pctx(key, data, ctx)
        normalized = Textus::Protocol::Format.data_to_payload(data, ctx.entry.format)
        meta = stamped_meta(normalized[:meta])
        @store_engine.put(key:, meta:, body: normalized[:body], content: normalized[:content], call: @call)
        Textus::Protocol::Manifest::Entry::Base::PublishContext.new(
          container: @container,
          reader: ->(key:) { @store_engine.read(key:) },
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

      def stamped_meta(meta)
        now = Time.now.utc.iso8601
        (meta || {}).merge("generated_at" => now)
      end
    end
  end
end
