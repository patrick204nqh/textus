Textus.workflow "contributing" do
  match "artifacts.contributing"

  step :build do |_, ctx|
    project_env = ctx.container.reader.read("knowledge.project")
    project = project_env&.meta || {}
    { "content" => { "project_name" => project["name"].to_s } }
  end

  publish
end
