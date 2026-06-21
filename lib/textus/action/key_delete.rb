# frozen_string_literal: true

module Textus
  module Action
    class KeyDelete < Unit
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

      def self.call(container:, call:, key:, if_etag: nil)
        Textus::Manifest::Data.validate_key!(key)
        mentry = container.manifest.resolver.resolve(key).entry

        container.compositor.delete(key, mentry: mentry, if_etag: if_etag, call: call)

        { "protocol" => Textus::PROTOCOL, "ok" => true, "key" => key, "deleted" => true }
      end
    end
  end
end
