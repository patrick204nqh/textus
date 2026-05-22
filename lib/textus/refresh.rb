require "timeout"

module Textus
  module Refresh
    FETCH_TIMEOUT_SECONDS = 2

    def self.call(store, key, as:) # rubocop:disable Metrics/AbcSize
      mentry, path, = store.manifest.resolve(key)
      raise UsageError.new("no intake declared for '#{key}'") unless mentry.intake_handler

      before_etag = File.exist?(path) ? Etag.for_file(path) : nil
      callable = store.registry.rpc_callable(:intake, mentry.intake_handler)
      view = Store::View.new(store, writable: true, as: as)

      store.fire_event(:refresh_started, key: key, mode: :sync)
      result =
        begin
          Timeout.timeout(FETCH_TIMEOUT_SECONDS) do
            callable.call(store: view, config: mentry.intake_config, args: {})
          end
        rescue Timeout::Error
          store.fire_event(:refresh_failed, key: key, error_class: "Timeout::Error",
                                            error_message: "intake '#{mentry.intake_handler}' exceeded #{FETCH_TIMEOUT_SECONDS}s")
          raise UsageError.new("intake '#{mentry.intake_handler}' exceeded #{FETCH_TIMEOUT_SECONDS}s timeout")
        rescue Textus::Error => e
          store.fire_event(:refresh_failed, key: key, error_class: e.class.name, error_message: e.message)
          raise
        rescue StandardError => e
          store.fire_event(:refresh_failed, key: key, error_class: e.class.name, error_message: e.message)
          raise UsageError.new("intake '#{mentry.intake_handler}' raised: #{e.class}: #{e.message}")
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
      store.fire_event(:refreshed, key: key, envelope: envelope, change: change) unless change == :unchanged
      envelope
    end

    # Normalize the three accepted intake return shapes into the store's
    # internal {frontmatter, body, content} representation.
    def self.normalize_action_result(res, format:)
      res = res.transform_keys(&:to_s) if res.is_a?(Hash)
      res ||= {}
      # Accept both legacy :frontmatter/:_meta key names from intake hooks.
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
          raise UsageError.new("intake for #{format} returned neither content nor body")
        end
      else
        raise UsageError.new("unknown format #{format.inspect}")
      end
    end
  end
end
