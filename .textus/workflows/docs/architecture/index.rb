Textus.workflow "architecture-index-generator" do
  match "artifacts.architecture.index"

  step :build do |_, ctx|
    data   = ctx.manifest.data
    policy = ctx.manifest.policy

    lanes = data.declared_lane_kinds.map do |name, kind|
      writers = policy.writers_for(name)
      { "name" => name.to_s, "kind" => kind.to_s,
        "purpose" => data.lane_descs[name].to_s, "writers" => writers.map(&:to_s) }
    end

    roles = data.role_caps.map do |role, caps|
      { "name" => role.to_s, "capabilities" => caps.map(&:to_s) }
    end

    { "content" => { "lanes" => lanes, "roles" => roles } }
  end
  publish to: "docs/architecture/README.md", template: "docs/architecture/index.erb"
end
