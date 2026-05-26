module Textus
  module Doctor
    class Check
      class SchemaViolations < Check
        def call
          res = Textus::Operations.for(store).validate_all
          res["violations"].map do |v|
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
