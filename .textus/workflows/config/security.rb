Textus.workflow "security" do
  match "artifacts.security"
  step(:build) { |_, _| { "content" => {} } }
  publish to: "SECURITY.md", template: "docs/meta/security.erb"
end
