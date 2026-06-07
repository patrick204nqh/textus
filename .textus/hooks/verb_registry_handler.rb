# Produces verb-reference data (ADR 0097/0098) from Read::Capabilities — the
# blessed machine-readable contract projection (lib/textus/read/capabilities.rb),
# the same surface CLI/MCP/boot derive from. Depends on that stable projection,
# NOT on Dispatcher::VERBS internals (DIP).
Textus.hook do |reg|
  reg.on(:resolve_handler, :verbs) do |**|
    projection = Textus::Read::Capabilities.new.call["verbs"]
    verbs = projection.map do |row|
      {
        "name" => row["verb"],
        "summary" => row["summary"].to_s,
        "args" => Array(row["args"]).map { |a| a["name"].to_s }.sort,
      }
    end
    { "content" => { "verbs" => verbs } }
  end
end
