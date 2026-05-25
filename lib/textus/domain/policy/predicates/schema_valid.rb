module Textus
  module Domain
    module Policy
      module Predicates
        class SchemaValid
          attr_reader :reason

          def name
            "schema_valid"
          end

          def call(entry:, store:)
            return true if entry.nil? || store.nil?

            target_key = entry.dig("_meta", "proposal", "target_key")
            return true unless target_key

            mentry, = store.manifest.resolve(target_key)
            schema_ref = mentry&.schema
            return true unless schema_ref

            schema = store.schema_for(schema_ref)
            return true unless schema

            frontmatter = entry.dig("_meta", "frontmatter") || {}
            begin
              schema.validate!(frontmatter)
            rescue Textus::SchemaViolation => e
              @reason = e.message.dup
              d = e.details
              if d.is_a?(Hash)
                if d["missing"]
                  @reason = "missing required fields: #{Array(d["missing"]).join(", ")}"
                elsif d["field"]
                  @reason = "field '#{d["field"]}': #{d["reason"]}"
                end
              end
              return false
            end

            true
          rescue StandardError => e
            @reason = "schema validation error: #{e.message}"
            false
          end
        end
      end
    end
  end
end
