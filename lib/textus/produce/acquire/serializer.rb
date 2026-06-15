module Textus
  module Produce
    module Acquire
      # Abstract base for output serializers. Each concrete serializer owns
      # producing the bytes for one manifest format (json/yaml/text).
      # Rendering through a template is a publish concern (ADR 0094) — serializers
      # here only serialize data; they take no arguments.
      class Serializer
        def call(mentry:, data:)
          _ = mentry
          _ = data
          raise NotImplementedError.new("#{self.class.name}#call not implemented")
        end
      end
    end
  end
end
