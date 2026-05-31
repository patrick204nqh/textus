require "spec_helper"

RSpec.describe "zone desc: surfaces in boot and survives rename (ADR 0033)" do
  include_context "textus_store_fixture"
  include TextusSpecHelpers

  let(:store) do
    store_from_manifest(root, zones: %w[knowledge], manifest: <<~YAML)
      version: textus/3
      roles: [{ name: human, can: [author] }]
      zones:
        - { name: knowledge, kind: canon, desc: "the maintained source of truth" }
    YAML
  end

  it "emits the manifest desc on the boot zone row" do
    row = store.as("human").boot["zones"].find { |z| z["name"] == "knowledge" }
    expect(row["purpose"]).to eq("the maintained source of truth")
  end

  it "omits purpose when no desc is declared" do
    dir2 = File.join(tmp, ".textus2")
    s = store_from_manifest(dir2, zones: %w[knowledge], manifest: <<~YAML)
      version: textus/3
      roles: [{ name: human, can: [author] }]
      zones:
        - { name: knowledge, kind: canon }
    YAML
    row = s.as("human").boot["zones"].find { |z| z["name"] == "knowledge" }
    expect(row).not_to have_key("purpose")
  end
end
