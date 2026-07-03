require "yaml"

# Replaces Doctor::Check::ProtocolVersion. Runs on drain and publishes to
# artifacts.doctor.protocol-version.

Textus.workflow "doctor-protocol-version" do
  match "artifacts.doctor.protocol-version"

  step :scan do |_, ctx|
    path = ctx.container.layout.manifest_path
    issues = []

    if File.exist?(path)
      doc = YAML.safe_load_file(path, aliases: false) || {}
      version = doc["version"]
      if version != "textus/4"
        issues << {
          "code" => "protocol_mismatch",
          "level" => "error",
          "subject" => path,
          "message" => "Store reports version=#{version.inspect}; this gem expects textus/4.",
          "fix" => "Upgrade the store's manifest version to textus/4 (see CHANGELOG for breaking changes).",
        }
      end
    end

    { "content" => { "ok" => issues.empty?, "issues" => issues, "count" => issues.size } }
  end

  publish
end
