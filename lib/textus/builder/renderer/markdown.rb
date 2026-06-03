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
          # Deterministic frontmatter only — `from` (the source keys), never a
          # volatile `generated.at` (ADR 0070): the artifact is content-addressed
          # so a rebuild is a byte-for-byte no-op and a revert never drifts.
          frontmatter = { "generated" => { "from" => from } }
          Entry.for_format("markdown").serialize(meta: frontmatter, body: body)
        end
      end
    end
  end
end
