module Textus
  module Protocol
    class Blueprint
      module Compiler
        SEGMENT_PATTERNS = {
          "sequential" => /\A\d{4}-[a-z][a-z0-9-]*\z/,
          "dated" => /\A\d{4}-\d{2}-\d{2}-[a-z][a-z0-9-]*\z/,
        }.freeze

        SEGMENT_EXAMPLES = {
          "sequential" => "0003-identity",
          "dated" => "2026-07-09-example",
        }.freeze

        module_function

        def compile(mentry, schemas:)
          naming = build_naming(mentry)
          schema = build_schema_view(mentry, schemas)

          Blueprint.new(
            key: mentry.key,
            lane: mentry.lane,
            naming: naming,
            format: mentry.format || "markdown",
            schema: schema,
            key_grammar: build_key_grammar,
            meta_template: build_meta_template(schema),
            template: build_template(mentry, naming, schema)
          )
        end

        def build_naming(mentry)
          pattern = SEGMENT_PATTERNS[mentry.naming]
          return nil unless pattern

          {
            alias: mentry.naming,
            pattern: pattern.source,
            example: SEGMENT_EXAMPLES[mentry.naming] || "example"
          }
        end

        def build_schema_view(mentry, schemas)
          return nil unless mentry.schema && schemas

          schema = schemas.fetch_or_nil(mentry.schema)
          return nil unless schema

          all_field_names = schema.required + schema.optional
          fields = all_field_names.map do |f|
            spec = schema.fields[f] || {}
            {
              name: f,
              type: spec["type"] || "string",
              required: schema.required.include?(f),
              desc: spec["description"] || spec["desc"] || ""
            }
          end

          { name: schema.name, fields: fields }
        end

        def build_key_grammar
          {
            max_segments: Key::Grammar::MAX_SEGMENTS,
            max_segment_len: Key::Grammar::MAX_SEGMENT_LEN,
            segment_pattern: Key::Grammar::SEGMENT.source
          }
        end

        def build_meta_template(schema)
          return "---\n---\n<body>" unless schema&.dig(:fields)

          required = schema[:fields].select { |f| f[:required] }
          return "---\n---\n<body>" if required.empty?

          fm = required.map { |f| "#{f[:name]}: <#{f[:name]}>" }.join("\n")
          "---\n#{fm}\n---\n<body>"
        end

        def build_template(mentry, naming, schema)
          seg = generate_segment(mentry)
          key = "#{mentry.key}.#{seg}"
          body = build_meta_template(schema)
          { key: key, body: body }
        end

        def generate_segment(mentry)
          case mentry.naming
          when "sequential" then "0000-example"
          when "dated" then Time.now.utc.strftime("%Y-%m-%d") + "-example"
          else "example"
          end
        end
      end
    end
  end
end
