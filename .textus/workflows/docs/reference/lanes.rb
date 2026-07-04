Textus.workflow "reference-lanes" do
  match "artifacts.reference.lanes"

  step :build do |_, ctx|
    kmap  = Textus::Manifest::Schema::Vocabulary::LANES
    lanes = build_lanes(ctx).map { |l| l.merge("capability" => kmap[l["kind"]] || "n/a") }
    roles = build_roles(ctx)
    { "content" => { "lanes" => lanes, "roles" => roles, "kind_capability_map" => kmap } }
  end
  publish to: "docs/reference/lanes.md", template: "docs/reference/lanes.erb"
end
