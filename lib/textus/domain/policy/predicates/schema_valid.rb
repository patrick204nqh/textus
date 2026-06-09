# frozen_string_literal: true

module Textus
  module Domain
    module Policy
      module Predicates
        # Predicate: the entry's effective metadata satisfies the schema
        # bound to the target key. For accept, the metadata lives under
        # envelope.meta["_meta"]; for a direct put it is envelope.meta.
        class SchemaValid
          attr_reader :reason

          def initialize(schemas:)
            @schemas = schemas
          end

          def name = "schema_valid"

          def call(eval)
            manifest = eval.manifest
            return true if eval.envelope.nil? || manifest.nil? || @schemas.nil?

            target_key = eval.target
            return true unless target_key

            mentry = manifest.resolver.resolve(target_key).entry
            schema_ref = mentry&.schema
            return true unless schema_ref

            schema = @schemas.fetch_or_nil(schema_ref)
            return true unless schema

            frontmatter =
              eval.envelope.meta&.dig("_meta") || eval.envelope.meta || {}
            begin
              schema.validate!(frontmatter)
              true
            rescue Textus::SchemaViolation => e
              @reason = humanize(e)
              false
            end
          rescue StandardError => e
            @reason = "schema validation error: #{e.message}"
            false
          end

          private

          def humanize(err)
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
