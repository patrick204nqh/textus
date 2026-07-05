module Textus
  module Protocol
    module EntryConstraint
      module_function

      def validate_naming!(key, mentry)
        naming = mentry.naming
        return unless naming
        return unless key.start_with?("#{mentry.key}.")

        last = key.split(".").last

        case naming
        when "sequential"
          return if last.match?(/\A\d{4}-[a-z][a-z0-9-]*\z/)

          raise UsageError.new(
            "naming violation: '#{key}' last segment must match NNNN-slug " \
            "(entry '#{mentry.key}' has naming: sequential)",
          )
        when "dated"
          return if last.match?(/\A\d{4}-\d{2}-\d{2}-[a-z][a-z0-9-]*\z/)

          raise UsageError.new(
            "naming violation: '#{key}' last segment must match YYYY-MM-DD-slug " \
            "(entry '#{mentry.key}' has naming: dated)",
          )
        end
      end

      def validate_schema!(payload, mentry, schemas:)
        schema_name = mentry.schema
        return unless schema_name && schemas

        schema = schemas.fetch_or_nil(schema_name)
        return unless schema
        return if mentry.lane == "scratchpad"

        schema.validate!(payload.meta || {})
      rescue Textus::SchemaViolation
        raise if mentry.lane != "scratchpad"
      end

      def validate_format!(payload, mentry, format: nil)
        fmt_name = format || mentry.format
        fmt = Textus::Protocol::Format.for(fmt_name)
        fmt.validate_raw_entry!(
          { "_meta" => payload.meta, "content" => payload.content },
          mentry.lane,
        )
      end
    end
  end
end
