require "spec_helper"

# Conformance for the textus/3 manifest zones block.
RSpec.describe "textus/3 conformance — zones block" do
  include_context "textus/3 conformance fixture"

  describe "zones block" do
    it "derives zone writers from capability × zone-kind" do
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/3
        zones:
          - { name: identity, kind: canon }
          - { name: proposals,  kind: queue }
        entries:
          - { key: identity.self, path: identity/self.md, zone: identity, owner: human:patrick, kind: leaf}

      YAML
      FileUtils.mkdir_p(File.join(root, "zones/identity"))
      File.write(File.join(root, "zones/identity/self.md"), "---\nname: self\n---\n")
      m = Textus::Manifest.load(root)
      # canon requires author; only human holds it under the default mapping.
      expect(m.policy.zone_writers("identity")).to eq(["human"])
      # queue requires propose; both human and agent hold it.
      expect(m.policy.zone_writers("proposals")).to contain_exactly("human", "agent")
    end

    it "raises BadFrontmatter if zones block is absent" do
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/3
        entries:
          - { key: state.x, path: state/x.md, zone: state, owner: human:self, kind: leaf}

      YAML
      expect { Textus::Manifest.load(root) }
        .to raise_error(Textus::BadFrontmatter, /manifest must declare zones/)
    end
  end
end
