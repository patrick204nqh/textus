Textus.workflow "code-of-conduct" do
  match "artifacts.code-of-conduct"
  step(:build) { |_, _| { "content" => {} } }
  publish
end
