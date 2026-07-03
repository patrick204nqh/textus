module Textus
  module Ingest
    module Handlers
      def self.ingest_url(store, url, title: nil, tags: [], via: nil)
        resolver = Resolver.new(store)
        resolver.ingest(url, kind: "link", title:, tags:, via:)
      end

      def self.ingest_asset(store, url, mime_type:, checksum:, title: nil)
        resolver = Resolver.new(store)
        resolver.ingest(url, kind: "asset", title:)
      end

      def self.ingest_text(store, url, text:, title: nil, tags: [], via: nil)
        resolver = Resolver.new(store)
        resolver.ingest(url, kind: "text", title:, tags:, via:, text:)
      end

      def self.lookup(store, url)
        Resolver.new(store).resolve(url)
      end
    end
  end
end
