Textus.workflow "reference-testing" do
  match "artifacts.reference.testing"
  step(:build) { |_, _| { "_meta" => { "uid" => Textus::VERSION }, "content" => {} } }
  publish
end
