module Textus
  module Protocol
    class StoreEngine
      module PutPipeline
        STEPS = [Validate, Prepare, Write, Emit].freeze

        def self.call(key, mentry:, path:, payload:, deps:, if_etag: nil, fmt: nil)
          ctx = Pipeline::WriteContext.new(
            key:, mentry:, payload:, if_etag:,
            path:, existing_env: nil, meta: nil, content: nil,
            bytes: nil, eff_meta: nil, eff_body: nil, eff_content: nil,
            etag_before: nil, envelope: nil, fmt:
          )
          STEPS.reduce(ctx) { |c, step| step.call(c, deps) }.envelope
        end
      end
    end
  end
end
