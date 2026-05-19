require "timeout"

module Textus
  module Refresh
    FETCHER_TIMEOUT_SECONDS = 2

    def self.call(store, key, as:)
      mentry, path, = store.manifest.resolve(key)
      raise UsageError.new("no fetcher declared for '#{key}'") unless mentry.fetcher

      before_etag = File.exist?(path) ? Etag.for_file(path) : nil
      callable = store.registry.fetcher(mentry.fetcher)
      view = StoreView.new(store)
      result =
        begin
          Timeout.timeout(FETCHER_TIMEOUT_SECONDS) { callable.call(config: mentry.fetcher_config, store: view) }
        rescue Timeout::Error
          raise UsageError.new("fetcher '#{mentry.fetcher}' exceeded #{FETCHER_TIMEOUT_SECONDS}s timeout")
        rescue Textus::Error
          raise
        rescue StandardError => e
          raise UsageError.new("fetcher '#{mentry.fetcher}' raised: #{e.class}: #{e.message}")
        end

      fm = result[:frontmatter] || result["frontmatter"] || {}
      body = result[:body] || result["body"] || ""
      envelope = store.put(key, frontmatter: fm, body: body, as: as, suppress_events: true)

      change = if before_etag.nil?
                 :created
               elsif envelope["etag"] == before_etag
                 :unchanged
               else
                 :updated
               end
      store.fire_event(:refresh, key: key, envelope: envelope, change: change) unless change == :unchanged
      envelope
    end
  end
end
