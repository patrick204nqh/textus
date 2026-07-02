Textus.workflow "how-to-migrations" do
  match "artifacts.how-to.migrations"
  step(:build) { |_, _| { "content" => {} } }
  publish to: "docs/how-to/migrations.md", template: "docs/how-to/migrations.erb"
end
