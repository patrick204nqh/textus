Textus.workflow "contributing" do
  match "artifacts.contributing"

  step :build do |_, ctx|
    project_env = ctx.container.reader.read("knowledge.project")
    project = project_env&.meta || {}
    uid = Digest::SHA1.hexdigest(project["name"].to_s)[0, 16]
    { "_meta" => { "uid" => uid },
      "content" => { "project_name" => project["name"].to_s } }
  end

  publish
end
