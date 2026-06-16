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


      def initialize(key:, if_etag: nil)
        super()
        @key = key
        @if_etag = if_etag
      end

      def call(container:, call:)
        run_with_cascade(@key, container:, call:) do
          Textus::Manifest::Data.validate_key!(@key)
          mentry = container.manifest.resolver.resolve(@key).entry

          auth(container).check_action!(action: :key_delete, actor: call.role, key: @key, extra: { if_etag: @if_etag })

          writer(container, call).delete(@key, mentry:, if_etag: @if_etag)

          { "protocol" => Textus::PROTOCOL, "ok" => true, "key" => @key, "deleted" => true }
        end
      end
    end
  end
end
