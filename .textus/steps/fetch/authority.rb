# Produces the authority-model reference (ADR 0112; on the verbs/schema/events
# pattern of ADR 0097/0098/0102) by PROJECTING the live truth — never retyped,
# so docs/reference/authority.md cannot drift. Three projections:
#
#   lanes — the zone-kind ↔ capability BIJECTION, verbatim from
#           Schema::Vocabulary::LANES (canon→author, workspace→keep,
#           machine→converge, queue→propose).
#   lanes — this manifest's declared lanes: name, kind, the capability that
#           kind requires (derived via LANES), and the optional desc.
#   roles — this manifest's declared roles: name, the can-set, and the
#           zone-kinds each role can write (the inverse of LANES over its can).
#
# Acquire-only (ADR 0094) — the publish template renders it. Reads from
# caps.manifest (roles/lanes) and the vocabulary constant (the bijection).
module Textus
  module Step
    class AuthorityFetch < Fetch
      def call(config:, args:, caps:, **)
        _ = config
        _ = args
        lanes_map = Textus::Manifest::Schema::Vocabulary::LANES
        raw = caps.manifest.data.raw

        lanes = lanes_map.map { |kind, capability| { "kind" => kind, "capability" => capability } }

        lanes_declared = Array(raw["lanes"]).map do |z|
          kind = z["kind"].to_s
          {
            "name" => z["name"].to_s,
            "kind" => kind,
            "capability" => lanes_map[kind].to_s,
            "desc" => z["desc"].to_s,
          }
        end

        roles = Array(raw["roles"]).map do |r|
          can = Array(r["can"]).map(&:to_s)
          # Inverse of the bijection: which zone-kinds this role's caps authorize.
          writes_kinds = can.filter_map { |cap| lanes_map.key(cap) }.sort
          { "name" => r["name"].to_s, "can" => can, "writes_kinds" => writes_kinds }
        end

        { "content" => { "lanes" => lanes, "zones" => lanes_declared, "roles" => roles } }
      end
    end
  end
end
