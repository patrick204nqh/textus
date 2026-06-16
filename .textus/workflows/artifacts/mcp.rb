Textus.workflow "mcp" do
  match "artifacts.mcp"

  step :build do |_, _ctx|
    maintenance_names = Textus::Surfaces::MCP::Catalog::MAINTENANCE_VERBS.to_set(&:to_s)

    fmt_args = lambda do |spec|
      parts = spec.args.map do |a|
        type = Textus::Contract::JSON_TYPES.fetch(a.type, a.type.to_s.downcase)
        "#{a.wire}#{"?" unless a.required}: #{type}"
      end
      parts.empty? ? "none" : parts.join(", ")
    end

    all_specs = Textus::Surfaces::MCP::Catalog.specs

    tools = all_specs.reject { |s| maintenance_names.include?(s.verb.to_s) }
                     .sort_by { |s| s.verb.to_s }
                     .map { |s| { "name" => s.verb.to_s, "summary" => s.summary.to_s, "args" => fmt_args.call(s) } }

    maintenance = all_specs.select { |s| maintenance_names.include?(s.verb.to_s) }
                           .sort_by { |s| s.verb.to_s }
                           .map { |s| { "name" => s.verb.to_s, "summary" => s.summary.to_s, "args" => fmt_args.call(s) } }

    { "content" => { "tools" => tools, "maintenance" => maintenance } }
  end

  publish
end
