module Textus
  module Builder
    # Abstract base for output renderers. Each concrete renderer owns
    # producing the bytes for one manifest format (json/yaml/text).
    # Rendering through a template is a publish concern (ADR 0094) — renderers
    # here only serialize data; they take no arguments.
    class Renderer
      def call(mentry:, data:)
        _ = mentry
        _ = data
        raise NotImplementedError.new("#{self.class.name}#call not implemented")
      end
    end
  end
end
