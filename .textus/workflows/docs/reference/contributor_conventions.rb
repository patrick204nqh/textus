Textus.workflow "reference-contributor-conventions" do
  match "artifacts.reference.contributor-conventions"
  step(:build) { |_, _| { "content" => {} } }
  publish
end
