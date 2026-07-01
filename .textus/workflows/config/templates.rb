# Replaces Doctor::Check::Templates. Checks every publish target template exists.

Textus.workflow "templates" do
  match "artifacts.doctor.templates"

  step :check do |_, ctx|
    manifest = ctx.container.manifest
    layout = ctx.container.layout
    issues = []
    manifest.data.entries.each do |entry|
      entry.publish_to.each do |target|
        tmpl = target.respond_to?(:template) ? target.template : nil
        next unless tmpl
        to_path = target.respond_to?(:to) ? target.to : target.to_s
        path = layout.template_path(tmpl)
        next if File.exist?(path)
        issues << { "code" => "publish.missing_template", "severity" => "warning",
                    "subject" => entry.key,
                    "message" => "publish target '#{to_path}' references missing template '#{tmpl}'",
                    "fix" => "create the template at #{path}" }
      end
    end
    { "content" => { "ok" => issues.empty?, "issues" => issues, "count" => issues.size } }
  end

  publish
end
