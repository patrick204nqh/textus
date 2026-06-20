# frozen_string_literal: true

module Textus
  module Action
    class Put < WriteVerb
      extend Textus::Contract::DSL

      verb :put
      summary "Create or update an entry. Schema-validated. Returns {uid, etag}."
      surfaces :cli, :mcp
      arg :key, String, required: true, positional: true,
                        description: "dotted entry key, e.g. 'knowledge.project'; must resolve to a zone the role may write"
      arg :meta, Hash, required: false, wire_name: :_meta,
                       description: "frontmatter; reads back as `_meta` from `get`. Schema-validated — call `schema KEY` first"
      arg :body, String,
          description: "markdown/text payload for markdown-format entries; omit (use `content`) for json/yaml entries. Do not send both"
      arg :content, Hash,
          description: "structured payload for json/yaml-format entries; omit (use `body`) for markdown entries. Do not send both"
      arg :if_etag, String,
          description: "optimistic-concurrency guard: the etag you last read; the write is rejected if the entry changed since"
      view { |env| { "uid" => env.uid, "etag" => env.etag } }

      def initialize(key:, meta: nil, body: nil, content: nil, if_etag: nil)
        super()
        @key = key
        @meta = meta
        @body = body
        @content = content
        @if_etag = if_etag
      end

      def call(container:, call:)
        run_with_cascade(@key, container:, call:) do
          Textus::Manifest::Data.validate_key!(@key)
          mentry = container.manifest.resolver.resolve(@key).entry
          envelope = writer(container, call).put(
            @key,
            mentry: mentry,
            payload: Textus::Store::Envelope::Writer::Payload.new(
              meta: @meta,
              body: @body,
              content: @content,
            ),
            if_etag: @if_etag,
          )

          envelope
        end
      end
    end
  end
end
