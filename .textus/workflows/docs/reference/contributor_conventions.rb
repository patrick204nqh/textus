Textus.workflow "reference-contributor-conventions" do
  match "artifacts.reference.contributor-conventions"
  step(:build) { |_, _| { "content" => {} } }
  publish to: "docs/reference/contributor-conventions.md", template: "docs/reference/contributor-conventions.erb"
end
