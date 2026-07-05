module Textus
  module Protocol
    class StoreEngine
      module PutPipeline
        module Validate
          def self.call(ctx, deps)
            ctx = validate_input(ctx, deps)
            validate_schema(ctx, deps)
          end

          def self.validate_input(ctx, _deps)
            fmt = Textus::Protocol::Format.for(ctx.mentry.format)
            fmt.enforce_name_match!(ctx.path, ctx.payload.meta)
            fmt.validate_raw_entry!(
              { "_meta" => ctx.payload.meta, "content" => ctx.payload.content },
              ctx.mentry.lane,
            )
            ctx
          end

          def self.validate_schema(ctx, deps)
            schema_name = ctx.mentry.schema
            return ctx unless schema_name && deps.respond_to?(:schemas) && deps.schemas

            schema = deps.schemas.fetch_or_nil(schema_name)
            return ctx unless schema

            case ctx.mentry.lane
            when "scratchpad"
              begin
                schema.validate!(ctx.payload.meta || {})
              rescue Textus::SchemaViolation # rubocop:disable Lint/SuppressedException
              end
            else
              schema.validate!(ctx.payload.meta || {})
            end
            ctx
          end
        end
      end
    end
  end
end
