require "json"

module Textus
  module Builder
    class Renderer
      class Json < Renderer
        def call(mentry:, data:)
          content = default_shape(mentry, data)
          final   = InjectMeta.call(content, mentry)
          Entry.for_format("json").serialize(meta: {}, body: "", content: final)
        end

        private

        def default_shape(mentry, data)
          has_transform = mentry.is_a?(Textus::Manifest::Entry::Derived) &&
                          mentry.source.projection? &&
                          mentry.source.transform
          if has_transform && data.is_a?(Hash) && !data.key?("entries")
            data
          elsif data.is_a?(Hash) && data["entries"].is_a?(Array)
            { "entries" => data["entries"] }
          else
            data.is_a?(Hash) ? data : { "entries" => Array(data) }
          end
        end
      end
    end
  end
end
