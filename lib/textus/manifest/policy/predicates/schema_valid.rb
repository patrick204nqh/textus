module Textus
  class Manifest
    class Policy
      module Predicates
        class SchemaValid
          def self.call(manifest:, actor:, action:, key:, schemas: nil, envelope: nil, extra: {})
            return { pass: true } unless envelope
            return { pass: true } if key.nil?

            mentry = manifest.resolver.resolve(key).entry
            schema_ref = mentry.schema
            return { pass: true } unless schema_ref
            return { pass: true } unless schemas

            schema = schemas.fetch_or_nil(schema_ref)
            return { pass: true } unless schema

            frontmatter = envelope.meta&.dig("_meta") || envelope.meta || {}
            begin
              schema.validate!(frontmatter)
              { pass: true }
            rescue Textus::SchemaViolation => e
              { pass: false, reason: schema_reason(e) }
            end
          rescue Textus::UnknownKey
            { pass: true }
          end

          def self.schema_reason(err)
            d = err.details
            return err.message.dup unless d.is_a?(Hash)
            return "missing required fields: #{Array(d["missing"]).join(", ")}" if d["missing"]
            return "field '#{d["field"]}': #{d["reason"]}" if d["field"]

            err.message.dup
          end
        end
      end
    end
  end
end
