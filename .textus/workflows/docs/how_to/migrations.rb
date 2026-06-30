Textus.workflow "how-to-migrations" do
  match "artifacts.how-to.migrations"
  step(:build) { |_, _| { "content" => {} } }
  publish
end
