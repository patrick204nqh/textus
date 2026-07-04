Textus.workflow "how-to-configuring-lanes" do
  on "artifacts.how-to.configuring-lanes"

  step :build do |_, ctx|
    kmap  = Textus::Manifest::Schema::Vocabulary::LANES
    lanes = build_lanes(ctx).map { |l| l.merge("capability" => kmap[l["kind"]] || "n/a") }
    roles = build_roles(ctx)
    { "content" => { "lanes" => lanes, "roles" => roles, "kind_capability_map" => kmap } }
  end
  publish to: "docs/how-to/configuring-lanes.md", template: "docs/how-to/configuring-lanes.erb"
end
