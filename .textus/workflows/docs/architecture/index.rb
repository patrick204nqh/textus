Textus.workflow "architecture-index-generator" do
  on "artifacts.architecture.index"

  step :build do |_, ctx|
    { "content" => { "lanes" => build_lanes(ctx), "roles" => build_roles(ctx) } }
  end
  publish to: "docs/architecture/README.md", template: "docs/architecture/index.erb"
end
