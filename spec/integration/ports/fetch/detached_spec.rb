require "spec_helper"

RSpec.describe Textus::Ports::Fetch::Detached do
  include_context "textus_store_fixture"

  describe ".acting_role" do
    it "resolves the ingest-holder by capability (a non-default holder)" do
      FileUtils.mkdir_p(File.join(root, "zones/feeds"))
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/3
        roles:
          - { name: agent, can: [propose, ingest] }
        zones:
          - { name: feeds, kind: quarantine }
        entries: []
      YAML
      store = Textus::Store.new(root)
      expect(described_class.acting_role(store)).to eq("agent")
    end

    it "returns nil when no role holds ingest" do
      FileUtils.mkdir_p(File.join(root, "zones/knowledge"))
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/3
        roles:
          - { name: human, can: [author, propose] }
        zones:
          - { name: knowledge, kind: canon }
        entries: []
      YAML
      store = Textus::Store.new(root)
      expect(described_class.acting_role(store)).to be_nil
    end
  end
end
