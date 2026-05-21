module Textus
  class Builder
    module Renderer
      class Text
        def initialize(template_loader:)
          @template_loader = template_loader
        end

        def call(mentry:, data:)
          raise TemplateError.new("entry '#{mentry.key}': text build requires a template") unless mentry.template

          body = Mustache.render(@template_loader.call(mentry.template), data)
          Entry.for_format("text").serialize(meta: {}, body: body)
        end
      end
    end
  end
end
