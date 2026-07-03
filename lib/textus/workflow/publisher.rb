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
          write_and_publish(key, data, ctx, targets, definition)
          return
        end

        blk = definition.publish_block
        return blk.call(data, ctx) if blk && blk != :default

        built_in_publish(key, data, ctx, definition)
      end

      private

      def write_and_publish(key, data, ctx, targets, _definition)
        normalized = Textus::Protocol::Format.data_to_payload(data, ctx.entry.format)
        @container.writer.put(key, mentry: ctx.entry,
                                   payload: Textus::Value::Payload.new(**normalized), call: @call)

        targets.each do |target|
          attrs = { "to" => target.to, "template" => target.template,
                    "tree" => target.tree }
          attrs["inject_boot"] = true if target.inject_boot
          pub_target = Textus::Manifest::Policy::PublishTarget.new(attrs)
          pctx = Textus::Manifest::Entry::Base::PublishContext.new(
            container: @container, call: @call,
            reader: @container.reader.method(:read)
          )
          entry = ctx.entry.with_publish_targets([pub_target])
          entry.publish_via(pctx)
        end
      end

      def built_in_publish(key, data, ctx, _definition)
        normalized = Textus::Protocol::Format.data_to_payload(data, ctx.entry.format)
        @container.writer.put(key, mentry: ctx.entry,
                                   payload: Textus::Value::Payload.new(**normalized), call: @call)

        entry = @container.manifest.resolver.resolve(key).entry
        return unless entry.publish_tree || !Array(entry.publish_to).empty?

        pctx = Textus::Manifest::Entry::Base::PublishContext.new(
          container: @container, call: @call,
          reader: @container.reader.method(:read)
        )
        entry.publish_via(pctx)
      end
    end
  end
end
