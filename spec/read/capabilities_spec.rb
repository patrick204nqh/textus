require "spec_helper"

RSpec.describe Textus::Read::Capabilities do
  subject(:result) { described_class.new.call }

  it "projects every contract-bearing dispatcher verb" do
    names = result["verbs"].map { |v| v["verb"] }
    expect(names).to include("where", "list", "put", "key_mv_prefix")

    with_contract = Textus::Dispatcher::VERBS.values.count do |k|
      k.respond_to?(:contract?) && k.contract?
    end
    expect(names.size).to eq(with_contract)
  end

  it "is sorted by verb name" do
    names = result["verbs"].map { |v| v["verb"] }
    expect(names).to eq(names.sort)
  end

  it "reports each verb's surfaces from the contract" do
    where = result["verbs"].find { |v| v["verb"] == "where" }
    expect(where["surfaces"]).to contain_exactly("cli", "ruby", "mcp")
    expect(where["cli"]).to eq("where")
  end

  it "surfaces the dry_run default asymmetry so it is self-documenting (F6)" do
    dry_run = result["verbs"]
              .find { |v| v["verb"] == "key_mv_prefix" }["args"]
              .find { |a| a["name"] == "dry_run" }
    expect(dry_run).to include("default" => true, "cli_default" => false)
  end

  it "carries the full arg schema (name, type, required, positional)" do
    key = result["verbs"].find { |v| v["verb"] == "where" }["args"].first
    expect(key).to include(
      "name" => "key", "type" => "string", "required" => true, "positional" => true,
    )
  end

  it "filters to a single verb when given one" do
    only = described_class.new.call(verb: "where")
    expect(only["verbs"].map { |v| v["verb"] }).to eq(["where"])
  end

  it "includes itself (it is MCP-surfaced)" do
    caps = result["verbs"].find { |v| v["verb"] == "capabilities" }
    expect(caps["surfaces"]).to include("mcp")
  end
end
