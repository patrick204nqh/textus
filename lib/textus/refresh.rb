module Textus
  module Refresh
    def self.call(store, key, as:)
      bus = Textus::Infra::EventBus.new(registry: store.registry)
      worker = Textus::Application::Refresh::Worker.new(store: store, bus: bus)
      worker.run(key, as: as)
    end

    def self.refresh_stale(store, prefix: nil, zone: nil, as: "script")
      Textus::Application::Refresh::All.call(store, prefix: prefix, zone: zone, as: as)
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
