# frozen_string_literal: true

require "spec_helper"
require "pathname"

# SSoT guards (ADR 0098): lanes.md is hand-authored prose but cites manifest
# facts. This asserts the doc covers every projected fact so it cannot silently
# drift from the manifest. The MCP tool catalog is now returned by boot
# (artifacts.ops(:boot)) rather than maintained in a generated reference doc.
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
end
