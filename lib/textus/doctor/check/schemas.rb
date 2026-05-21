module Textus
  module Doctor
    class Check
      class Schemas < Check
        def call
          out = []
          store.manifest.entries.each do |entry|
            next if entry.schema.nil?

            sp = File.join(store.root, "schemas", "#{entry.schema}.yaml")
            next if File.exist?(sp)

            out << {
              "code" => "schema.missing",
              "level" => "error",
              "subject" => entry.key,
              "message" => "schema '#{entry.schema}' not found at #{sp}",
              "fix" => "create the schema file or run 'textus schema init #{entry.schema} --from=<key>'",
            }
          end
          out
        end
      end
    end
  end
end
