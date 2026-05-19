# Assembles a Claude Code marketplace.json document from three projection sources:
#   - canon.marketplace          → name, owner
#   - canon.plugin               → plugin name/description for the single listing
#   - working.skills.<...>       → the per-skill source paths under ./skills/
Textus.reducer(:"marketplace-envelope") do |rows:, config:|
  _ = config

  market = rows.find { |r| r["_key"] == "canon.marketplace" } || {}
  plugin = rows.find { |r| r["_key"] == "canon.plugin" } || {}
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
