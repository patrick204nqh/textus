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

      normalized = normalize_fetcher_result(result, format: mentry.format)
      envelope = store.put(
        key,
        frontmatter: normalized[:frontmatter],
        body: normalized[:body],
        content: normalized[:content],
        as: as,
        suppress_events: true,
      )

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

    # Normalize the three accepted fetcher return shapes into the store's
    # internal {frontmatter, body, content} representation. See plan-1.2 §7.
    def self.normalize_fetcher_result(res, format:)
      res = res.transform_keys(&:to_s) if res.is_a?(Hash)
      res ||= {}
      fm      = res["frontmatter"]
      body    = res["body"]
      content = res["content"]

      case format
      when "markdown"
        { frontmatter: fm || {}, body: body.to_s, content: nil }
      when "text"
        { frontmatter: {}, body: body.to_s, content: nil }
      when "json", "yaml"
        if !content.nil?
          meta = content.is_a?(Hash) && content["_meta"].is_a?(Hash) ? content["_meta"] : {}
          { frontmatter: meta, body: nil, content: content }
        elsif !body.nil?
          # Store#put will re-parse and validate the bytes.
          { frontmatter: {}, body: body.to_s, content: nil }
        else
          raise UsageError.new("fetcher for #{format} returned neither content nor body")
        end
      else
        raise UsageError.new("unknown format #{format.inspect}")
      end
    end
  end
end
