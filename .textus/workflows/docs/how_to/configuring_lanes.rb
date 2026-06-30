Textus.workflow "how-to-configuring-lanes" do
  match "artifacts.how-to.configuring-lanes"

  step :build do |_, ctx|
    data   = ctx.container.manifest.data
    policy = ctx.container.manifest.policy
    kmap   = Textus::Manifest::Schema::Vocabulary::LANES

    lanes = data.declared_lane_kinds.map do |name, kind|
      cap     = kmap[kind.to_s]
      writers = cap ? policy.roles_with_capability(cap).map(&:to_s) : []
      { "name" => name.to_s, "kind" => kind.to_s,
        "purpose" => data.lane_descs[name].to_s, "capability" => cap.to_s, "writers" => writers }
    end

    roles = data.role_caps.map do |role, caps|
      { "name" => role.to_s, "capabilities" => caps.map(&:to_s) }
    end

    { "content" => { "lanes" => lanes, "roles" => roles, "kind_capability_map" => kmap } }
  end

  publish
end
