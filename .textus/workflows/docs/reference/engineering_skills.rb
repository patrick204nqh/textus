Textus.workflow "reference-engineering-skills" do
  match "artifacts.reference.engineering-skills"
  step(:build) { |_, _| { "_meta" => { "uid" => Textus::VERSION }, "content" => {} } }
  publish
end
