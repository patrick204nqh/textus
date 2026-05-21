module Textus
  module Doctor
    class Check
      class UnownedSchemaFields < Check
        def call
          out = []
          dir = File.join(store.root, "schemas")
          return out unless File.directory?(dir)

          Dir.glob(File.join(dir, "*.yaml")).sort.each do |sp| # rubocop:disable Lint/RedundantDirGlobSort
            schema = begin
              Schema.load(sp)
            rescue StandardError
              next
            end
            unowned = schema.fields.each_with_object([]) do |(name, spec), acc|
              acc << name if spec.is_a?(Hash) && spec["maintained_by"].nil?
            end
            next if unowned.empty?

            out << {
              "code" => "schema.unowned_fields",
              "level" => "info",
              "subject" => schema.name || File.basename(sp, ".yaml"),
              "message" => "schema has fields without maintained_by: #{unowned.join(", ")}",
              "fix" => "add 'maintained_by: <role>' to each field in #{sp} (optional but recommended)",
            }
          end
          out
        end
      end
    end
  end
end
