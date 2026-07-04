module Textus
  module Lanes
    module Ingest
      module Handlers
        SOURCE_KINDS = %w[url file asset].freeze

        module_function

        def ingest(kind:, slug:, ctx:, call:, url: nil, path: nil, lane: nil, label: nil)
          raise Textus::UsageError.new("kind must be one of #{SOURCE_KINDS.join("|")}") unless SOURCE_KINDS.include?(kind)

          case kind
          when "url"   then raise Textus::UsageError.new("url required") unless url
          when "file"  then raise Textus::UsageError.new("path required") unless path
          when "asset"
            raise Textus::UsageError.new("path required") unless path
            raise Textus::UsageError.new("lane required") unless lane
          end

          now = Time.now.utc
          key = KeyBuilder.derive_key(now, kind, slug)
          content_hash = KeyBuilder.compute_hash(kind:, url:, path:)
          mentry = ctx.mentry_for(key)

          entry_type = EntryTypes.for(kind)
          time = now
          structured = entry_type.build(url:, path:, lane:, label:, time:, layout: ctx.layout)

          lookup = Textus::Infra::Store::Index::Lookup.new(ctx.store.db)
          duplicate_key = Dedup.find(lookup, content_hash, url:)

          if duplicate_key && duplicate_key != key
            old_content = ctx.read(duplicate_key)&.content || {}
            Resolver.supersede(duplicate_key, key, ctx, call:)

            if kind == "asset"
              EntryTypes::Asset.move(old_content["asset"], lane, ctx.layout) if old_content["asset"]
            end

            old_count = old_content["ingest_count"] || 1
            structured["ingest_count"] = old_count + 1
            structured["duplicated_at"] = now.utc.iso8601
            structured["supersedes"] = duplicate_key
          else
            structured["ingest_count"] = 1
          end

          env = ctx.write(key, mentry:, call:,
                               payload: ctx.payload(meta: nil, body: nil, content: structured))

          IndexRebuilder.rebuild!(ctx.store.db, ctx.manifest.resolver)

          { "key" => key, "uid" => env.uid, "etag" => env.etag }
        end
      end
    end
  end
end
