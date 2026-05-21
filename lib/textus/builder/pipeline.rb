require "time"

module Textus
  class Builder
    module InjectMeta
      # Returns a new hash with _meta as the first key, per SPEC §6 ordering.
      def self.call(content_hash, mentry)
        meta = { "generated_at" => Time.now.utc.iso8601 }
        from = Array(mentry.projection&.fetch("select", nil)).compact
        meta["from"] = from unless from.empty?
        meta["template"] = mentry.template if mentry.template
        reduce = mentry.projection&.dig("reduce")
        meta["reduce"] = reduce if reduce

        out = { "_meta" => meta }
        content_hash.each { |k, v| out[k] = v unless k == "_meta" }
        out
      end
    end
  end
end
