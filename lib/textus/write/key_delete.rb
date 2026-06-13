module Textus
  module Write
    class KeyDelete
      extend Textus::Contract::DSL

      verb     :key_delete
      summary  "Delete one entry by key. Single-key, lower blast radius than " \
               "key_delete_prefix; guarded by an optional optimistic-concurrency etag. Returns {ok, key, deleted}."
      surfaces :cli, :mcp
      cli      "key delete"
      arg :key, String, required: true, positional: true,
                        description: "dotted entry key to delete"
      arg :if_etag, String,
          description: "optimistic-concurrency guard: the etag you last read; the delete is rejected if the entry changed since"
      # `call` already returns a wire hash {protocol, ok, key, deleted}; identity response.

      def initialize(container:, call:)
        @container    = container
        @call         = call
        @manifest     = container.manifest
        @steps = container.steps
      end

      def call(key, if_etag: nil, suppress_events: false)
        Textus::Manifest::Data.validate_key!(key)
        mentry = @manifest.resolver.resolve(key).entry

        auth.check!(action: :key_delete, actor: @call.role, key: key, extra: { if_etag: if_etag })

        writer.delete(key, mentry: mentry, if_etag: if_etag)

        unless suppress_events
          @steps.publish(:entry_deleted,
                         ctx: hook_context,
                         key: key)
        end

        { "protocol" => Textus::PROTOCOL, "ok" => true, "key" => key, "deleted" => true }
      end

      private

      def auth
        @auth ||= Textus::Dispatch::Auth.new(manifest: @manifest, schemas: @container.schemas)
      end

      def hook_context
        @hook_context ||= Textus::Step::Context.for(container: @container, call: @call)
      end

      def writer
        @writer ||= Textus::Envelope::IO::Writer.from(container: @container, call: @call)
      end
    end
  end
end
