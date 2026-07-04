module Textus
  module Workflow
    class Publisher
      def initialize(container:, call:)
        @container = container
        @call      = call
      end

      def publish(key, data, ctx, definition)
        targets = definition.publish_targets
        if targets.any?
          targets.each { |t| publish_one(key, data, ctx, target: t) }
          return
        end

        blk = definition.publish_block
        return blk.call(data, ctx) if blk && blk != :default

        built_in_publish(key, data, ctx)
      end

      private

      def write_and_pctx(key, data, ctx)
        normalized = Textus::Protocol::Format.data_to_payload(data, ctx.entry.format)
        payload = Textus::Value::Payload.new(**normalized)
        @container.writer.put(key, mentry: ctx.entry, payload:, call: @call)
        Textus::Protocol::Manifest::Entry::Base::PublishContext.new(
          container: @container, call: @call,
          reader: @container.reader.method(:read)
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

      def built_in_publish(key, data, ctx)
        pctx = write_and_pctx(key, data, ctx)
        entry = @container.manifest.resolver.resolve(key).entry
        return unless entry.publish_tree || !Array(entry.publish_to).empty?

        entry.publish_via(pctx)
      end
    end
  end
end
