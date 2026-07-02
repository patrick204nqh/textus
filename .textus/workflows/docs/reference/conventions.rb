Textus.workflow "reference-conventions" do
  match "artifacts.reference.conventions"
  step(:build) { |_, _| { "content" => {} } }
  publish to: "docs/reference/conventions.md", template: "docs/reference/conventions.erb"
end
