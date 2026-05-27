require "time"

module Textus
  module Builder
    class Renderer
      class Markdown < Renderer
        def call(mentry:, data:)
          raise TemplateError.new("entry '#{mentry.key}': markdown build requires a template") unless mentry.template

          body = Mustache.render(@template_loader.call(mentry.template), data)
          from = if mentry.is_a?(Textus::Manifest::Entry::Derived) &&
                    mentry.source.is_a?(Textus::Manifest::Entry::Derived::Projection)
                   Array(mentry.source.select).compact
                 else
                   []
                 end
          frontmatter = {
            "generated" => {
              "at" => Time.now.utc.iso8601,
              "from" => from,
            },
          }
          Entry.for_format("markdown").serialize(meta: frontmatter, body: body)
        end
      end
    end
  end
end
