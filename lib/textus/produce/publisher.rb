module Textus
  module Produce
    module Publisher
      def self.call(container:, call:, key:)
        entry = container.manifest.resolver.resolve(key).entry
        return unless entry.publish_tree || !Array(entry.publish_to).empty?

        entry_path = container.manifest.resolver.resolve(key).path
        return unless entry.publish_tree || container.file_store.exists?(entry_path)

        reader = Textus::Store::Entry::Reader.from(container: container)
        pctx = Textus::Manifest::Entry::Base::PublishContext.new(
          container: container,
          call: call,
          reader: reader.method(:read),
        )
        entry.publish_via(pctx)
      end
    end
  end
end
