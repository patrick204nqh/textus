module Textus
  module Doctor
    class Check
      class Templates < Check
        def call
          out = []
          store.manifest.entries.each do |entry|
            next if entry.template.nil?

            tp = File.join(store.root, "templates", entry.template)
            next if File.exist?(tp)

            out << {
              "code" => "template.missing",
              "level" => "error",
              "subject" => entry.key,
              "message" => "template '#{entry.template}' not found at #{tp}",
              "fix" => "create the file at #{tp} or update the entry's template: field",
            }
          end
          out
        end
      end
    end
  end
end
