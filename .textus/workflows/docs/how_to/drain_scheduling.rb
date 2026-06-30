Textus.workflow "how-to-drain-scheduling" do
  match "artifacts.how-to.drain-scheduling"
  step(:build) { |_, _| { "_meta" => { "uid" => Textus::VERSION }, "content" => {} } }
  publish
end
