require "json"

module Textus
  module Builder
    class Renderer
      class Json < Renderer
        def call(mentry:, data:)
          content = mentry.template ? parse_rendered_template!(mentry, data) : default_shape(mentry, data)
          final = InjectMeta.call(content, mentry)
          Entry.for_format("json").serialize(meta: {}, body: "", content: final)
        end

        private

        def parse_rendered_template!(mentry, data)
          rendered = Mustache.render(@template_loader.call(mentry.template), data)
          begin
            parsed = ::JSON.parse(rendered)
          rescue ::JSON::ParserError => e
            raise BadRender.new("entry '#{mentry.key}': template did not render valid json: #{e.message}", format: "json")
          end
          unless parsed.is_a?(Hash)
            raise BadRender.new("entry '#{mentry.key}': template must render a top-level object/mapping",
                                format: "json")
          end

          parsed
        end

        def default_shape(mentry, data)
          if mentry.projection && mentry.projection["reduce"] && data.is_a?(Hash) && !data.key?("entries")
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
