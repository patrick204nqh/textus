Textus.workflow "how-to-migrations" do
  match "artifacts.how-to.migrations"
  step(:build) { |_, _| { "_meta" => { "uid" => Textus::VERSION }, "content" => {} } }
  publish
end
