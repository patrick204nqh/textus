Textus.workflow "explanation-concepts" do
  match "artifacts.explanation.concepts"

  step :build do |_, ctx|
    require "digest"

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

    propose_lane = policy.propose_lane_for("agent").to_s
    canonical    = lanes.map { |l| l["name"] }.join + propose_lane
    uid          = Digest::SHA1.hexdigest(canonical)[0, 16]

    { "_meta" => { "uid" => uid },
      "content" => { "lanes" => lanes, "roles" => roles, "propose_lane" => propose_lane } }
  end

  publish
end
