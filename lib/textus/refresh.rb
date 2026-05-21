require "timeout"

module Textus
  module Refresh
    FETCH_TIMEOUT_SECONDS = 2

    def self.call(store, key, as:)
      mentry, path, = store.manifest.resolve(key)
      # TODO: Task 5 — rename to fetch
      raise UsageError.new("no fetch declared for '#{key}'") unless mentry.action

      before_etag = File.exist?(path) ? Etag.for_file(path) : nil
      # TODO: Task 5 — rename to fetch
      callable = store.registry.rpc_callable(:fetch, mentry.action)
      view = StoreView.new(store, writable: true, as: as)
      result =
        begin
          Timeout.timeout(FETCH_TIMEOUT_SECONDS) do
            # TODO: Task 5 — rename to fetch_config
            callable.call(store: view, config: mentry.action_config, args: {})
          end
        rescue Timeout::Error
          raise UsageError.new("fetch '#{mentry.action}' exceeded #{FETCH_TIMEOUT_SECONDS}s timeout")
        rescue Textus::Error
          raise
        rescue StandardError => e
          raise UsageError.new("fetch '#{mentry.action}' raised: #{e.class}: #{e.message}")
        end

      normalized = normalize_action_result(result, format: mentry.format)
      envelope = store.put(
        key,
        meta: normalized[:meta],
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

    # Normalize the three accepted fetch return shapes into the store's
    # internal {frontmatter, body, content} representation.
    def self.normalize_action_result(res, format:)
      res = res.transform_keys(&:to_s) if res.is_a?(Hash)
      res ||= {}
      # Accept both legacy :frontmatter/:_meta key names from fetch hooks.
      meta_val = res["_meta"] || res["frontmatter"]
      body    = res["body"]
      content = res["content"]

      case format
      when "markdown"
        { meta: meta_val || {}, body: body.to_s, content: nil }
      when "text"
        { meta: {}, body: body.to_s, content: nil }
      when "json", "yaml"
        if !content.nil?
          { meta: meta_val || {}, body: nil, content: content }
        elsif !body.nil?
          { meta: {}, body: body.to_s, content: nil }
        else
          raise UsageError.new("fetch for #{format} returned neither content nor body")
        end
      else
        raise UsageError.new("unknown format #{format.inspect}")
      end
    end
  end
end
