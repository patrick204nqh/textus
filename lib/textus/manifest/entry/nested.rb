require_relative "validators/publish_each"

module Textus
  class Manifest
    class Entry
      class Nested < Base
        PUBLISH_EACH_VARS   = Validators::PublishEach::KNOWN_VARS
        PUBLISH_EACH_VAR_RE = Validators::PublishEach::VAR_RE

        attr_reader :index_filename, :publish_each

        def initialize(index_filename: nil, publish_each: nil, **rest)
          super(**rest)
          @index_filename = index_filename
          @publish_each = publish_each
        end

        def nested? = true

        def publish_target_for(full_key)
          return nil if @publish_each.nil?

          entry_segs = @key.split(".")
          key_segs = full_key.split(".")
          raise UsageError.new("key '#{full_key}' is not under entry '#{@key}'") unless key_segs[0, entry_segs.length] == entry_segs

          remaining = key_segs[entry_segs.length..] || []
          leaf = remaining.join("/")
          basename = remaining.last || ""
          ext = Textus::Entry.for_format(@format).extensions.first.to_s.sub(/^\./, "")

          vars = { "leaf" => leaf, "basename" => basename, "key" => full_key, "ext" => ext }
          @publish_each.gsub(PUBLISH_EACH_VAR_RE) { vars.fetch(::Regexp.last_match(1)) }
        end
      end
    end
  end
end
