# frozen_string_literal: true

require "spec_helper"
require "pathname"

# SSoT guards (ADR 0098): events.md / zones.md / mcp.md are hand-authored prose,
# but the facts they cite have machine projections. These assert the docs cover
# every projected fact, so a doc cannot silently drift from the code.
RSpec.describe "reference doc facts cover their projections" do
  let(:repo) { Pathname.new(File.expand_path("../../..", __dir__)) }

  def read_doc(rel)
    (repo + rel).read
  end

  let(:catalog_events) do
    (Textus::Hooks::Catalog::PUBSUB.keys + Textus::Hooks::Catalog::RPC.keys).map(&:to_s)
  end

  # `:event`-shaped tokens cited inside markdown table rows (lines starting with
  # `|`) of a doc — the catalog/failure tables list events there, and table rows
  # never carry the hook-handler names that appear in prose/code blocks (e.g.
  # `:rank_by_recency`), so this stays precise.
  def event_tokens_in_tables(doc)
    doc.lines.select { |l| l.lstrip.start_with?("|") }
       .flat_map { |l| l.scan(/`:([a-z_]+)`/).flatten }.uniq
  end

  it "events.md documents every Hooks::Catalog event" do
    doc = read_doc("docs/reference/events.md")
    missing = catalog_events.reject { |n| doc.include?(n) }
    expect(missing).to be_empty, "events.md missing: #{missing.join(", ")}"
  end

  it "events.md cites no event absent from Hooks::Catalog (no stale rows)" do
    stale = event_tokens_in_tables(read_doc("docs/reference/events.md")) - catalog_events
    expect(stale).to be_empty,
                     "events.md tables cite events not in Hooks::Catalog: #{stale.join(", ")}"
  end

  it "the README hook tables cite only real Hooks::Catalog events" do
    stale = event_tokens_in_tables(read_doc("README.md")) - catalog_events
    expect(stale).to be_empty,
                     "README cites events not in Hooks::Catalog: #{stale.join(", ")}"
  end

  it "zones.md documents every manifest zone" do
    doc = read_doc("docs/reference/zones.md")
    zones = Textus::Manifest.load((repo + ".textus").to_s).data.declared_zone_kinds.keys
    missing = zones.map(&:to_s).reject { |z| doc.include?(z) }
    expect(missing).to be_empty, "zones.md missing: #{missing.join(", ")}"
  end

  it "mcp.md documents every MCP tool" do
    doc = read_doc("docs/reference/mcp.md")
    tools = Textus::MCP::ToolSchemas.all.map { |t| (t[:name] || t["name"]).to_s }
    missing = tools.reject { |t| t.empty? || doc.include?(t) }
    expect(missing).to be_empty, "mcp.md missing: #{missing.join(", ")}"
  end
end
