module Textus
  module Builder
    # Abstract base for output renderers. Each concrete renderer owns
    # producing the bytes for one manifest format (markdown/json/yaml/text).
    class Renderer
      def initialize(template_loader:)
        @template_loader = template_loader
      end

      def call(mentry:, data:)
        _ = mentry
        _ = data
        raise NotImplementedError.new("#{self.class.name}#call not implemented")
      end
    end
  end
end
