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

  it "lanes.md documents every manifest lane" do
    doc = read_doc("docs/reference/lanes.md")
    lanes = Textus::Manifest.load((repo + ".textus").to_s).data.declared_lane_kinds.keys
    missing = lanes.map(&:to_s).reject { |z| doc.include?(z) }
    expect(missing).to be_empty, "lanes.md missing: #{missing.join(", ")}"
  end

  it "mcp.md documents every MCP tool" do
    doc = read_doc("docs/reference/mcp.md")
    tools = Textus::Surface::MCP::Catalog.names
    missing = tools.reject { |t| t.empty? || doc.include?(t) }
    expect(missing).to be_empty, "mcp.md missing: #{missing.join(", ")}"
  end
end
