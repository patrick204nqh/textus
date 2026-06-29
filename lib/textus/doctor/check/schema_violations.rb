module Textus
  module Doctor
    class Check
      class SchemaViolations < Check
        def call
          result = Textus::Doctor::Validator.new(
            reader: ->(key, ctnr, _c) { Textus::Store::Entry::Reader.from(container: ctnr).read(key) },
            manifest: @container.manifest,
            audit_log: @container.audit_log,
            schema_for: ->(name) { @container.schemas.fetch_or_nil(name) },
          ).call(container: @container, call: Textus::Value::Call.build(role: Textus::Value::Role::DEFAULT))

          result["violations"].map do |v|
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
        end
      end
    end
  end
end
