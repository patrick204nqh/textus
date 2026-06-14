module Textus
  module Pipeline
    module Acquire
      class Serializer
        class Text < Serializer
          def call(mentry:, data:) # rubocop:disable Lint/UnusedMethodArgument
            # Text format serializes data as plain-text. Rendering through a
            # template is a publish concern (ADR 0094) — build emits data only.
            body = data.is_a?(Hash) ? data.to_s : data.inspect
            Entry.for_format("text").serialize(meta: {}, body: body)
          end
        end
      end
    end
  end
end
