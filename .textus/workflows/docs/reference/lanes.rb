Textus.workflow "reference-lanes" do
  match "artifacts.reference.lanes"

  step :build do |_, ctx|
    data   = ctx.manifest.data
    policy = ctx.manifest.policy
    kmap   = Textus::Manifest::Schema::Vocabulary::LANES

    lanes = data.declared_lane_kinds.map do |name, kind|
      cap     = kmap[kind.to_s]
      writers = policy.writers_for(name).map(&:to_s)
      { "name" => name.to_s, "kind" => kind.to_s,
        "purpose" => data.lane_descs[name].to_s, "capability" => cap || "n/a", "writers" => writers }
    end

    roles = data.role_caps.map do |role, caps|
      { "name" => role.to_s, "capabilities" => caps.map(&:to_s) }
    end

    { "content" => { "lanes" => lanes, "roles" => roles, "kind_capability_map" => kmap } }
  end
  publish to: "docs/reference/lanes.md", template: "docs/reference/lanes.erb"
end
