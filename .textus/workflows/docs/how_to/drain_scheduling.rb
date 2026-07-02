Textus.workflow "how-to-drain-scheduling" do
  match "artifacts.how-to.drain-scheduling"
  step(:build) { |_, _| { "content" => {} } }
  publish to: "docs/how-to/drain-scheduling.md", template: "docs/how-to/drain-scheduling.erb"
end
