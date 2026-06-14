# frozen_string_literal: true

module Textus
  module Action
    class KeyDelete < WriteVerb
      extend Textus::Contract::DSL

      verb :key_delete
      summary "Delete one entry by key. Single-key, lower blast radius than key_delete_prefix; " \
              "guarded by an optional optimistic-concurrency etag. Returns {ok, key, deleted}."
      surfaces :cli, :mcp
      cli "key delete"
      arg :key, String, required: true, positional: true,
                        description: "dotted entry key to delete"
      arg :if_etag, String,
          description: "optimistic-concurrency guard: the etag you last read; the delete is rejected if the entry changed since"

      BURN = :sync

      def initialize(key:, if_etag: nil)
        super()
        @key = key
        @if_etag = if_etag
      end

      def args
        { key: @key, if_etag: @if_etag }.compact
      end

      def call(container:, call:)
        run_with_cascade(@key, container:, call:) do
          Textus::Manifest::Data.validate_key!(@key)
          mentry = container.manifest.resolver.resolve(@key).entry

          auth(container).check!(action: :key_delete, actor: call.role, key: @key, extra: { if_etag: @if_etag })

          writer(container, call).delete(@key, mentry:, if_etag: @if_etag)

          container.steps.publish(
            :entry_deleted,
            ctx: Textus::Step::Context.for(container: container, call: call),
            key: @key,
          )

          { "protocol" => Textus::PROTOCOL, "ok" => true, "key" => @key, "deleted" => true }
        end
      end

      private

      def auth(container)
        Textus::Dispatch::Auth.new(manifest: container.manifest, schemas: container.schemas)
      end

      def writer(container, call)
        Textus::Envelope::IO::Writer.from(container: container, call: call)
      end
    end
  end
end
