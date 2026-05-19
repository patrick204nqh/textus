require "timeout"

module Textus
  module Refresh
    FETCHER_TIMEOUT_SECONDS = 2

    def self.call(store, key, as:)
      mentry, = store.manifest.resolve(key)
      raise UsageError.new("no fetcher declared for '#{key}'") unless mentry.fetcher

      callable = store.registry.fetcher(mentry.fetcher)
      view = StoreView.new(store)
      result =
        begin
          Timeout.timeout(FETCHER_TIMEOUT_SECONDS) { callable.call(config: mentry.fetcher_config, store: view) }
        rescue Timeout::Error
          raise UsageError.new("fetcher '#{mentry.fetcher}' exceeded #{FETCHER_TIMEOUT_SECONDS}s timeout")
        end

      fm = result[:frontmatter] || result["frontmatter"] || {}
      body = result[:body] || result["body"] || ""
      store.put(key, frontmatter: fm, body: body, as: as)
    end
  end
end
