Textus.workflow "reference-testing" do
  match "artifacts.reference.testing"
  step(:build) { |_, _| { "content" => {} } }
  publish
end
