require "spec_helper"

RSpec.describe "Textus::Manifest grammar" do
  describe "version mismatch hints" do
    it "raises BadFrontmatter with the generic hint for any unsupported version" do
      yaml = "version: textus/2\nlanes: []\nentries: []\n"
      expect { Textus::Manifest.parse(yaml) }.to raise_error(Textus::BadFrontmatter) { |err|
        expect(err.message).to match(%r{unsupported manifest version "textus/2"})
        expect(err.hint).to match(/syntax errors/)
        expect(err.hint).not_to match(/0\.11\.x/)
      }
    end
  end

  describe "zones block" do
    include_context "textus/4 conformance fixture"

    it "derives zone writers from capability × zone-kind" do
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/4
        lanes:
          - { name: identity, kind: canon }
          - { name: proposals,  kind: queue }
        entries:
          - { key: identity.self, path: identity/self.md, lane: identity, owner: human:patrick, kind: leaf}

      YAML
      FileUtils.mkdir_p(File.join(root, "data/identity"))
      File.write(File.join(root, "data/identity/self.md"), "---\nname: self\n---\n")
      m = Textus::Manifest.load(root)
      # canon requires author; only human holds it under the default mapping.
      expect(m.policy.roles_with_capability(m.policy.verb_for_lane("identity"))).to eq(["human"])
      # queue requires propose; both human and agent hold it.
      expect(m.policy.roles_with_capability(m.policy.verb_for_lane("proposals"))).to contain_exactly("human", "agent")
    end

    it "raises BadFrontmatter if zones block is absent" do
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/4
        entries:
          - { key: state.x, path: state/x.md, lane: state, owner: human:self, kind: leaf}

      YAML
      expect { Textus::Manifest.load(root) }
        .to raise_error(Textus::BadFrontmatter, /manifest must declare lanes/)
    end
  end

  describe "zone desc (ADR 0033)" do
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
      row = store.as("human").boot["lanes"].find { |z| z["name"] == "knowledge" }
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
      row = s.as("human").boot["lanes"].find { |z| z["name"] == "knowledge" }
      expect(row).not_to have_key("purpose")
    end
  end
end
