module Textus
  module Write
    class Put
      extend Textus::Contract::DSL

      verb     :put
      summary  "Create or update an entry. Schema-validated. Returns {uid, etag}."
      surfaces :cli, :mcp
      arg :key,     String, required: true, positional: true,
                            description: "dotted entry key, e.g. 'knowledge.project'; must resolve to a zone the role may write"
      arg :meta,    Hash, required: false, wire_name: :_meta,
                          description: "frontmatter; reads back as `_meta` from `get`. Schema-validated — call `schema KEY` first"
      arg :body,    String,
          description: "markdown/text payload for markdown-format entries; omit (use `content`) for json/yaml entries. Do not send both"
      arg :content, Hash,
          description: "structured payload for json/yaml-format entries; omit (use `body`) for markdown entries. Do not send both"
      arg :if_etag, String,
          description: "optimistic-concurrency guard: the etag you last read; the write is rejected if the entry changed since"
      view { |env| { "uid" => env.uid, "etag" => env.etag } }

      def initialize(container:, call:)
        @container    = container
        @call         = call
        @manifest     = container.manifest
        @events       = container.events
      end

      def call(key, meta: nil, body: nil, content: nil, if_etag: nil)
        Textus::Manifest::Data.validate_key!(key)
        mentry = @manifest.resolver.resolve(key).entry
        guard_for(:put, key, if_etag: if_etag).check!(eval_for(:put, target_key: key))

        envelope = writer.put(
          key,
          mentry: mentry,
          payload: Textus::Envelope::IO::Writer::Payload.new(
            meta: meta, body: body, content: content,
          ),
          if_etag: if_etag,
        )

        @events.publish(:entry_put,
                        ctx: hook_context,
                        key: key,
                        envelope: envelope)

        envelope
      end

      private

      def guard_for(transition, key, if_etag: nil)
        Textus::Domain::Policy::GuardFactory.new(
          manifest: @manifest, schemas: @container.schemas, extra: { if_etag: if_etag },
        ).for(transition, key)
      end

      def eval_for(transition, target_key:, envelope: nil)
        Textus::Domain::Policy::Evaluation.new(
          actor: @call.role, transition: transition, origin: nil,
          target: target_key, envelope: envelope, manifest: @manifest
        )
      end

      def hook_context
        @hook_context ||= Textus::Hooks::Context.for(container: @container, call: @call)
      end

      def writer
        @writer ||= Textus::Envelope::IO::Writer.from(container: @container, call: @call)
      end
    end
  end
end
