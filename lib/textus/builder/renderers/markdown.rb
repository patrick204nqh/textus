require "time"

module Textus
  class Builder
    module Renderer
      class Markdown
        def initialize(template_loader:)
          @template_loader = template_loader
        end

        def call(mentry:, data:)
          raise TemplateError.new("entry '#{mentry.key}': markdown build requires a template") unless mentry.template

          body = Mustache.render(@template_loader.call(mentry.template), data)
          frontmatter = {
            "generated" => {
              "at" => Time.now.utc.iso8601,
              "from" => Array(mentry.projection&.fetch("select", nil)).compact,
            },
          }
          Entry.for_format("markdown").serialize(meta: frontmatter, body: body)
        end
      end
    end
  end
end
