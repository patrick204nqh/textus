require "yaml"

module Textus
  module Builder
    class Renderer
      class Yaml < Renderer
        def call(mentry:, data:)
          content = default_shape(mentry, data)
          final   = InjectMeta.call(content, mentry)
          Entry.for_format("yaml").serialize(meta: {}, body: "", content: final)
        end

        private

        def default_shape(mentry, data)
          has_transform = mentry.projection? &&
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
