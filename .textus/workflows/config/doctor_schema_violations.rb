# rubocop:disable Metrics/BlockLength
# Replaces Doctor::Check::SchemaViolations. Validates frontmatter against
# declared schemas for every resolvable key.

Textus.workflow "doctor-schema-violations" do
  match "artifacts.doctor.schema-violations"

  step :scan do |_, ctx|
    manifest = ctx.container.manifest
    schemas = ctx.container.schemas
    reader = ctx.container.reader

    violations = manifest.resolver.enumerate(include_keyless: true).filter_map do |row|
      key = row[:key]
      envelope = reader.read(key)
      next unless envelope

      schema_ref = envelope.schema_ref
      next unless schema_ref

      schema = schemas.fetch_or_nil(schema_ref)
      next unless schema

      frontmatter = envelope.meta&.dig("_meta") || envelope.meta || {}
      begin
        schema.validate!(frontmatter)
        nil
      rescue Textus::SchemaViolation => e
        {
          "code" => "schema_violation",
          "level" => "error",
          "subject" => key,
          "message" => "#{schema_ref}: #{e.message}",
          "fix" => "update _meta to satisfy schema '#{schema_ref}'",
        }
      end
    end

    { "content" => { "ok" => violations.empty?, "issues" => violations, "count" => violations.size } }
  end

  publish
end
# rubocop:enable Metrics/BlockLength
