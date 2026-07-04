Textus.workflow "render" do
  match "artifacts.render.**"
  step(:render) { |_, _| {} }
  publish to: "docs/reference/conventions.md", template: "docs/reference/conventions.erb"
  publish to: "docs/reference/testing.md", template: "docs/reference/testing.erb"
  publish to: "docs/reference/engineering-skills.md", template: "docs/reference/engineering-skills.erb"
  publish to: "docs/reference/contributor-conventions.md", template: "docs/reference/contributor-conventions.erb"
  publish to: "docs/how-to/drain-scheduling.md", template: "docs/how-to/drain-scheduling.erb"
  publish to: "docs/how-to/migrations.md", template: "docs/how-to/migrations.erb"
  publish to: "CODE_OF_CONDUCT.md", template: "docs/meta/code-of-conduct.erb"
  publish to: "SECURITY.md", template: "docs/meta/security.erb"
end
