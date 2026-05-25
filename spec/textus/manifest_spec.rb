require "spec_helper"

RSpec.describe Textus::Manifest do
  describe "textus/3 zone validation" do
    it "accepts intake as a canonical zone name" do
      yaml = <<~Y
        version: textus/3
        zones:
          - { name: intake, write_policy: [runner], read_policy: [all] }
        entries: []
      Y
      expect { described_class.parse(yaml) }.not_to raise_error
    end

    it "rejects legacy 'inbox' zone with a migration hint" do
      yaml = <<~Y
        version: textus/3
        zones:
          - { name: inbox, write_policy: [runner], read_policy: [all] }
        entries: []
      Y
      expect { described_class.parse(yaml) }
        .to raise_error(Textus::BadManifest, /inbox.*renamed to.*intake/i)
    end
  end

  describe "textus/3 zone policy fields" do
    let(:base) { <<~Y }
      version: textus/3
      zones:
        - { name: working, write_policy: [human, agent, runner], read_policy: [all] }
      entries: []
    Y

    it "parses write_policy and read_policy" do
      mf = described_class.parse(base)
      expect(mf.zone_writers("working")).to contain_exactly("human", "agent", "runner")
      perm = mf.permission_for("working")
      expect(perm.write_policy).to contain_exactly("human", "agent", "runner")
      expect(perm.read_policy).to eq(["all"])
    end

    it "rejects legacy writable_by with migration hint" do
      yaml = base.sub("write_policy: [human, agent, runner]", "writable_by: [human, agent, runner]")
      expect { described_class.parse(yaml) }
        .to raise_error(Textus::BadManifest, /writable_by.*renamed to.*write_policy/)
    end

    it "rejects legacy readable_by with migration hint" do
      yaml = base.sub("read_policy: [all]", "readable_by: [all]")
      expect { described_class.parse(yaml) }
        .to raise_error(Textus::BadManifest, /readable_by.*renamed to.*read_policy/)
    end
  end
end
