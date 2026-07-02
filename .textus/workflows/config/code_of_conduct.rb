Textus.workflow "code-of-conduct" do
  match "artifacts.code-of-conduct"
  step(:build) { |_, _| { "content" => {} } }
  publish to: "CODE_OF_CONDUCT.md", template: "docs/meta/code-of-conduct.erb"
end
