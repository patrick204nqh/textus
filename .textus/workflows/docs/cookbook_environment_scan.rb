Textus.workflow "cookbook-environment-scan" do
  match "artifacts.cookbook.environment-scan"
  step(:build) { |_, _| { "_meta" => { "uid" => Textus::VERSION }, "content" => {} } }
  publish
end
