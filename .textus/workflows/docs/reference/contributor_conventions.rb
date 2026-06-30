Textus.workflow "reference-contributor-conventions" do
  match "artifacts.reference.contributor-conventions"
  step(:build) { |_, _| { "_meta" => { "uid" => Textus::VERSION }, "content" => {} } }
  publish
end
