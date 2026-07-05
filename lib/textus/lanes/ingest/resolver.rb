module Textus
  module Lanes
    module Ingest
      module Resolver
        module_function

        def supersede(old_key, new_key, store:, ctx:, call:) # rubocop:disable Lint/UnusedMethodArgument
          old_env = store.read(key: old_key)
          old_content = old_env&.content || {}
          tombstone = {}
          %w[ingested_at ingest_count].each { |k| tombstone[k] = old_content[k] if old_content.key?(k) }
          source_kind = old_content.dig("source", "kind")
          tombstone["source"] = { "kind" => source_kind } if source_kind
          tombstone["superseded_by"] = new_key

          store.put(key: old_key, meta: {}, body: nil, content: tombstone, call:)
        end
      end
    end
  end
end
