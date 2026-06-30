Textus.workflow "architecture-index-generator" do
  match "artifacts.architecture.index"

  step :build do |_, ctx|
    data   = ctx.container.manifest.data
    policy = ctx.container.manifest.policy

    kind_to_cap = Textus::Manifest::Schema::Vocabulary::LANES

    lanes = data.declared_lane_kinds.map do |name, kind|
      cap     = kind_to_cap[kind.to_s]
      writers = cap ? policy.roles_with_capability(cap) : []
      { "name" => name.to_s, "kind" => kind.to_s,
        "purpose" => data.lane_descs[name].to_s, "writers" => writers.map(&:to_s) }
    end

    roles = data.role_caps.map do |role, caps|
      { "name" => role.to_s, "capabilities" => caps.map(&:to_s) }
    end

    { "content" => { "lanes" => lanes, "roles" => roles } }
  end

  publish
end
