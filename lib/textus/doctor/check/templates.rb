module Textus
  module Doctor
    class Check
      class Templates < Check
        def call
          out = []
          manifest.data.entries.each do |entry|
            entry.publish_targets.each do |target|
              template = target.template
              next if template.nil?

              tp = geometry.template_path(template)
              next if File.exist?(tp)

              out << {
                "code" => "template.missing",
                "level" => "error",
                "subject" => entry.key,
                "message" => "template '#{template}' not found at #{tp}",
                "fix" => "create the file at #{tp} or update the publish target's template: field",
              }
            end
          end
          out
        end
      end
    end
  end
end
