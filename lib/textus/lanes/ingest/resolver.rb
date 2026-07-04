module Textus
  module Lanes
    module Ingest
      module Resolver
        module_function

        def supersede(old_key, new_key, ctx, call:)
          old_mentry = ctx.mentry_for(old_key)
          old_env = ctx.read(old_key)
          old_content = old_env&.content || {}
          tombstone = {}
          %w[ingested_at ingest_count].each { |k| tombstone[k] = old_content[k] if old_content.key?(k) }
          source_kind = old_content.dig("source", "kind")
          tombstone["source"] = { "kind" => source_kind } if source_kind
          tombstone["superseded_by"] = new_key

          ctx.write(old_key, mentry: old_mentry, call:,
                             payload: ctx.payload(meta: nil, body: nil, content: tombstone))
        end
      end
    end
  end
end
