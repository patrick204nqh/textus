# Assembles a Claude Code marketplace.json document from three projection sources:
#   - identity.marketplace       → name, owner
#   - identity.plugin            → plugin name/description for the single listing
#   - working.skills.<...>       → the per-skill source paths under ./skills/
Textus.on(:transform_rows, :marketplace_envelope) do |rows:, **|
  market = rows.find { |r| r["_key"] == "identity.marketplace" } || {}
  plugin = rows.find { |r| r["_key"] == "identity.plugin" } || {}
  skills = rows
           .select { |r| r["_key"].to_s.start_with?("working.skills.") }
           .map    { |r| "./skills/#{r["name"]}" }
           .sort

  {
    "$schema" => "https://code.claude.com/schemas/marketplace.json",
    "name"    => market["name"],
    "owner"   => market["owner"],
    "plugins" => [
      {
        "name"        => plugin["name"],
        "source"      => "./",
        "description" => plugin["description"],
        "skills"      => skills,
      },
    ],
  }
end
