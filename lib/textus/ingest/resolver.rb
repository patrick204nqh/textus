module Textus
  module Ingest
    module Resolver
      module_function

      def supersede(old_key, new_key, container, call:)
        old_mentry = container.manifest.resolver.resolve(old_key).entry
        old_env = container.reader.read(old_key)
        old_content = old_env&.content || {}
        tombstone = {}
        %w[ingested_at].each { |k| tombstone[k] = old_content[k] if old_content.key?(k) }
        source_kind = old_content.dig("source", "kind")
        tombstone["source"] = { "kind" => source_kind } if source_kind
        tombstone["superseded_by"] = new_key

        container.writer.put(old_key, mentry: old_mentry, call:,
                                      payload: Textus::Value::Payload.new(meta: nil, body: nil, content: tombstone))
      end
    end
  end
end
