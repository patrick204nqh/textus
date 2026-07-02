Textus.workflow "reference-engineering-skills" do
  match "artifacts.reference.engineering-skills"
  step(:build) { |_, _| { "content" => {} } }
  publish to: "docs/reference/engineering-skills.md", template: "docs/reference/engineering-skills.erb"
end
