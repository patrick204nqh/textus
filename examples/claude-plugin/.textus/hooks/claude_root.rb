require "time"

# Groups projection rows for the CLAUDE.md template. Returns a Hash, so the
# projection bypasses sort/limit and the builder hands the Hash straight to
# Mustache. `generated_at` is stamped here because Projection only stamps it
# for the array path.
Textus.on(:transform_rows, :claude_root) do |rows:, **|
  by_prefix = ->(prefix) {
    rows.select { |r| r["_key"].to_s.start_with?(prefix) }
        .sort_by { |r| r["name"].to_s }
  }

  {
    "plugin"       => rows.find { |r| r["_key"] == "identity.plugin" } || {},
    "agents"       => by_prefix.call("working.agents."),
    "skills"       => by_prefix.call("working.skills."),
    "commands"     => by_prefix.call("working.commands."),
    "generated_at" => Time.now.utc.iso8601,
  }
end
