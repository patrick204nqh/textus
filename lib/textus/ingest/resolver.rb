module Textus
  module Ingest
    class Resolver
      def initialize(store)
        @store = store
      end

      def resolve(url)
        @store.list(prefix: "raw").select { |e|
          entry = @store.get(key: e[:key])
          entry&.content.is_a?(Hash) && entry.content["url"] == url
        }.map { |e| { key: e[:key], ingested_at: e[:ingested_at] } }
      end

      def ingest(url, kind:, title: nil, tags: [], via: nil, text: nil, asset_path: nil)
        date = Time.now.utc.strftime("%Y/%m/%d")
        slug = title ? title.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-\z/, "") : Digest::SHA256.hexdigest(url)[0..12]
        key = "raw.#{date}.#{slug}"

        existing = resolve(url)
        meta = { "supersedes" => existing.last[:key] } if existing.any?

        content = { "url" => url, "kind" => kind, "ingested_at" => Time.now.utc.iso8601 }
        content["title"] = title if title
        content["tags"] = tags if tags.any?
        content["via"] = via if via
        content["text"] = text if text

        { key:, content:, meta: meta || {} }
      end
    end
  end
end
