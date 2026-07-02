require "spec_helper"

RSpec.describe "Textus::Manifest grammar" do
  describe "version mismatch hints" do
    it "raises BadFrontmatter with the generic hint for any unsupported version" do
      yaml = "version: textus/2\nlanes: []\nentries: []\n"
      expect { Textus::Manifest.parse(yaml) }.to raise_error(Textus::BadFrontmatter) { |err|
        expect(err.message).to include('unsupported manifest version "textus/2"')
        expect(err.hint).to include("syntax errors")
        expect(err.hint).not_to include("0.11.x")
      }
    end
  end

  describe "writers_for" do
    include_context "textus/4 conformance fixture"

    it "returns writers for a fixed lane" do
      m = Textus::Manifest.load(root)
      expect(m.policy.writers_for("proposals")).to contain_exactly("human", "agent")
    end
  end

  describe "zone desc" do
    include_context "textus_store_fixture"

    let(:store) do
      store_from_manifest(root, lanes: %w[knowledge], manifest: <<~YAML)
        version: textus/4
        roles: [{ name: human, can: [author] }]
        lanes:
          - { name: knowledge, kind: canon, desc: "the maintained source of truth" }
      YAML
    end

    it "emits the manifest desc on the boot zone row" do
      row = store.with_role("human").boot["lanes"].find { |z| z["name"] == "knowledge" }
      expect(row["purpose"]).to eq("the maintained source of truth")
    end

    it "omits purpose when no desc is declared" do
      dir2 = File.join(tmp, ".textus2")
      s = store_from_manifest(dir2, lanes: %w[knowledge], manifest: <<~YAML)
        version: textus/4
        roles: [{ name: human, can: [author] }]
        lanes:
          - { name: knowledge, kind: canon }
      YAML
      row = s.with_role("human").boot["lanes"].find { |z| z["name"] == "knowledge" }
      expect(row).not_to have_key("purpose")
    end
  end
end
