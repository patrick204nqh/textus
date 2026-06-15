Textus.workflow "authority" do
  match "artifacts.derived.authority"

  step :fetch do |data, ctx|
    lanes_map    = Textus::Manifest::Schema::Vocabulary::LANES
    raw          = ctx.container.manifest.data.raw

    bijection = lanes_map.map { |kind, cap| { "kind" => kind, "capability" => cap } }

    lanes_declared = Array(raw["lanes"]).map do |z|
      kind = z["kind"].to_s
      {
        "name"       => z["name"].to_s,
        "kind"       => kind,
        "capability" => lanes_map[kind].to_s,
        "desc"       => z["desc"].to_s,
      }
    end

    roles = Array(raw["roles"]).map do |r|
      can         = Array(r["can"]).map(&:to_s)
      writes_kinds = can.filter_map { |cap| lanes_map.key(cap) }.sort
      { "name" => r["name"].to_s, "can" => can, "writes_kinds" => writes_kinds }
    end

    { "content" => { "lanes" => bijection, "zones" => lanes_declared, "roles" => roles } }
  end

  publish
end
