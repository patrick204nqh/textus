Textus.workflow "mcp" do
  match "artifacts.mcp"

  step :build do |_, _ctx|
    maintenance_names = Textus::Surfaces::MCP::Catalog::MAINTENANCE_VERBS.to_set(&:to_s)

    def fmt_args(spec)
      parts = spec.args.map do |a|
        type = Textus::Contract::JSON_TYPES.fetch(a.type, a.type.to_s.downcase)
        "#{a.wire}#{"?" unless a.required}: #{type}"
      end
      parts.empty? ? "none" : parts.join(", ")
    end

    all_specs = Textus::Surfaces::MCP::Catalog.specs

    tools = all_specs.reject { |s| maintenance_names.include?(s.verb.to_s) }.map do |s|
      { "name" => s.verb.to_s, "summary" => s.summary.to_s, "args" => fmt_args(s) }
    end

    maintenance = all_specs.select { |s| maintenance_names.include?(s.verb.to_s) }.map do |s|
      { "name" => s.verb.to_s, "summary" => s.summary.to_s, "args" => fmt_args(s) }
    end

    { "content" => { "tools" => tools, "maintenance" => maintenance } }
  end

  publish
end
