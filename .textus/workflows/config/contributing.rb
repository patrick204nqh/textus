Textus.workflow "contributing" do
  match "artifacts.contributing"

  step :build do |_, ctx|
    project_env = ctx.read("knowledge.loop.intent.0003-identity")
    project = project_env&.meta || {}
    { "content" => { "project_name" => project["name"].to_s } }
  end
  publish to: "CONTRIBUTING.md", template: "docs/meta/contributing.erb"
end
