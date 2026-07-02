# Replaces Doctor::Check::SchemaViolations. Validates entry data against
# declared schemas and role-authority constraints.

# rubocop:disable Metrics/BlockLength
Textus.workflow "doctor-schema-violations" do
  match "artifacts.doctor.schema-violations"

  step :scan do |_, ctx|
    result = Textus::Doctor::Validator.new(
      reader: lambda { |key, ctnr, _c|
        Textus::Store::Entry::Reader.new(
          file_store: ctnr.file_store,
          manifest: ctnr.manifest,
          layout: ctnr.layout,
        ).read(key)
      },
      manifest: ctx.container.manifest,
      audit_log: ctx.container.audit_log,
      schema_for: ->(name) { ctx.container.schemas.fetch_or_nil(name) },
    ).call(container: ctx.container, call: Textus::Value::Call.build(role: Textus::Value::Role::DEFAULT))

    issues = result.fetch("violations").map do |v|
      fix = v["expected"] &&
            "field '#{v["field"]}' should be written by '#{v["expected"]}' (last writer: #{v["last_writer"]})"
      {
        "code" => v["code"],
        "level" => "error",
        "subject" => v["key"],
        "message" => v["message"] || "#{v["code"]} on #{v["key"]}",
        "fix" => fix,
      }.compact
    end

    { "content" => { "ok" => issues.empty?, "issues" => issues, "count" => issues.size } }
  end

  publish
end
# rubocop:enable Metrics/BlockLength
