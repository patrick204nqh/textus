# Projects this repo's opencode configuration (opencode.json)
# from canon (ADR 0086 mirror): registers the textus MCP server
# and includes OPENCODE.md in the instructions.
Textus.hook do |reg|
  reg.on(:transform_rows, :opencode_config_reducer) do |rows:, **|
    rows.find { |r| r["_key"] == "knowledge.project" } || {}
    {
      mcp: {
        textus: {
          type: "local",
          command: %w[textus mcp serve],
          enabled: true,
        },
      },
      instructions: ["OPENCODE.md"],
    }
  end
end
