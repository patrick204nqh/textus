module Textus
  module Refresh
    def self.call(store, key, as:)
      ctx = Textus::Composition.context(store, role: as)
      Textus::Composition.refresh_worker(ctx).run(key)
    end

    def self.refresh_stale(store, prefix: nil, zone: nil, as: "script")
      ctx = Textus::Composition.context(store, role: as)
      Textus::Application::Refresh::All.call(ctx, prefix: prefix, zone: zone)
    end

    # Normalize the three accepted intake return shapes into the store's
    # internal {frontmatter, body, content} representation.
    def self.normalize_action_result(res, format:)
      res = res.transform_keys(&:to_s) if res.is_a?(Hash)
      res ||= {}
      meta_val = res["_meta"]
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
