Textus.workflow "reference-conventions" do
  match "artifacts.reference.conventions"
  step(:build) { |_, _| { "_meta" => { "uid" => Textus::VERSION }, "content" => {} } }
  publish
end
