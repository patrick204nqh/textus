require "spec_helper"

RSpec.describe Textus::Manifest::Capabilities do
  describe ".resolve" do
    describe "default mapping (no roles: block)" do
      let(:caps) { described_class.resolve(nil) }

      it "maps human → [author, propose]" do
        expect(caps["human"]).to eq(%w[author propose])
      end

      it "maps agent → [propose]" do
        expect(caps["agent"]).to eq(%w[propose])
      end

      it "maps automation → [converge]" do
        expect(caps["automation"]).to eq(%w[converge])
      end

      it "returns nil for unknown role names" do
        expect(caps["nobody"]).to be_nil
      end
    end

    describe "user-declared roles: block" do
      it "parses each role to name → [verbs]" do
        raw = [
          { "name" => "human",      "can" => %w[author propose] },
          { "name" => "automation", "can" => %w[converge] },
        ]
        caps = described_class.resolve(raw)
        expect(caps["human"]).to eq(%w[author propose])
        expect(caps["automation"]).to eq(%w[converge])
      end

      it "does not fall back to defaults when roles: is declared" do
        caps = described_class.resolve([{ "name" => "human", "can" => %w[author] }])
        expect(caps["human"]).to eq(%w[author]) # the declared caps, not the default [author, propose]
        expect(caps["agent"]).to be_nil
        expect(caps["automation"]).to be_nil
      end

      it "treats a missing can: as no capabilities" do
        caps = described_class.resolve([{ "name" => "agent" }])
        expect(caps["agent"]).to eq([])
      end
    end

    describe "empty roles: []" do
      it "yields an empty capability map" do
        expect(described_class.resolve([])).to eq({})
      end
    end
  end

  describe "parsing through Textus::Manifest.parse" do
    def parse(yaml)
      Textus::Manifest.parse(yaml)
    end

    it "flows the default mapping into Data#role_caps" do
      m = parse(<<~YAML)
        version: textus/3
        zones:
          - { name: identity, kind: canon }
          - { name: proposals,   kind: queue }
          - { name: artifacts,   kind: machine }
        entries: []
      YAML
      expect(m.data.role_caps).to eq(
        "human" => %w[author propose],
        "agent" => %w[propose],
        "automation" => %w[converge],
      )
    end

    it "parses a roles: block to name → [verbs]" do
      m = parse(<<~YAML)
        version: textus/3
        roles:
          - { name: human,      can: [author, propose] }
          - { name: automation, can: [converge] }
        zones:
          - { name: identity, kind: canon }
          - { name: artifacts,   kind: machine }
        entries: []
      YAML
      expect(m.data.role_caps).to eq(
        "human" => %w[author propose],
        "automation" => %w[converge],
      )
    end

    it "raises BadManifest on a verb outside CAPABILITIES" do
      yaml = <<~YAML
        version: textus/3
        roles:
          - { name: human, can: [author, teleport] }
        zones:
          - { name: identity, kind: canon }
        entries: []
      YAML
      expect { parse(yaml) }.to raise_error(Textus::BadManifest, /teleport/)
    end

    it "accepts every verb in the closed capability set" do
      yaml = <<~YAML
        version: textus/3
        roles:
          - { name: human, can: [propose, author, keep, converge] }
        zones:
          - { name: identity, kind: canon }
        entries: []
      YAML
      expect { parse(yaml) }.not_to raise_error
    end
  end
end
