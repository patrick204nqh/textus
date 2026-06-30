Textus.workflow "code-of-conduct" do
  match "artifacts.code-of-conduct"
  step(:build) { |_, _| { "_meta" => { "uid" => Textus::VERSION }, "content" => {} } }
  publish
end
