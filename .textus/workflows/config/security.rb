Textus.workflow "security" do
  match "artifacts.security"
  step(:build) { |_, _| { "content" => {} } }
  publish
end
