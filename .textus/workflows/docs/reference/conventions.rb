Textus.workflow "reference-conventions" do
  match "artifacts.reference.conventions"
  step(:build) { |_, _| { "content" => {} } }
  publish
end
