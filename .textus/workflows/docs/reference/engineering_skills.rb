Textus.workflow "reference-engineering-skills" do
  match "artifacts.reference.engineering-skills"
  step(:build) { |_, _| { "content" => {} } }
  publish
end
