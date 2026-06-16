require "spec_helper"

RSpec.describe Textus::Manifest::Policy do
  subject(:policy) { described_class.new(data) }

  let(:yaml) do
    <<~YAML
      version: textus/3
      roles:
        - { name: human,      can: [author, propose] }
        - { name: automation, can: [converge] }
      lanes:
        - { name: knowledge, kind: canon }
        - { name: review,  kind: machine }
      entries:
        - { key: knowledge.notes, path: knowledge/notes.md, lane: knowledge, owner: human:self, kind: leaf }
    YAML
  end
  let(:raw) { YAML.safe_load(yaml, aliases: false) }
  let(:data) { Textus::Manifest::Data.parse(raw, root: ".") }

  describe "#verb_for_lane" do
    it "maps each zone to the capability its kind requires" do
      expect(policy.verb_for_lane("knowledge")).to eq("author")
      expect(policy.verb_for_lane("review")).to eq("converge")
    end
  end

  describe "#roles_with_capability" do
    it "lists roles holding a given verb" do
      expect(policy.roles_with_capability("author")).to eq(["human"])
      expect(policy.roles_with_capability("propose")).to eq(["human"])
      expect(policy.roles_with_capability("converge")).to eq(["automation"])
    end
  end

  describe "#proposer_role" do
    it "prefers a non-author proposer over an author+propose role" do
      # default-style: human=[author,propose], agent=[propose] → agent wins
      raw2 = YAML.safe_load(<<~YAML, aliases: false)
        version: textus/3
        roles:
          - { name: human, can: [author, propose] }
          - { name: agent, can: [propose] }
        lanes:
          - { name: knowledge, kind: canon }
          - { name: review,  kind: queue }
        entries: []
      YAML
      p2 = described_class.new(Textus::Manifest::Data.parse(raw2, root: "."))
      expect(p2.proposer_role).to eq("agent")
    end

    it "falls back to the first proposer when the only proposer also holds author" do
      raw2 = YAML.safe_load(<<~YAML, aliases: false)
        version: textus/3
        roles:
          - { name: human, can: [author, propose] }
        lanes:
          - { name: knowledge, kind: canon }
          - { name: review,  kind: queue }
        entries: []
      YAML
      p2 = described_class.new(Textus::Manifest::Data.parse(raw2, root: "."))
      expect(p2.proposer_role).to eq("human")
    end

    it "returns nil when no role holds propose" do
      raw2 = YAML.safe_load(<<~YAML, aliases: false)
        version: textus/3
        roles:
          - { name: automation, can: [converge] }
        lanes:
          - { name: artifacts, kind: machine }
        entries: []
      YAML
      p2 = described_class.new(Textus::Manifest::Data.parse(raw2, root: "."))
      expect(p2.proposer_role).to be_nil
    end
  end

  describe "#actor_for" do
    it "returns the sole role holding the verb" do
      expect(policy.actor_for("converge")).to eq("automation")
      expect(policy.actor_for("author")).to eq("human")
    end

    it "returns the first declared holder when several roles hold the verb" do
      raw2 = YAML.safe_load(<<~YAML, aliases: false)
        version: textus/3
        roles:
          - { name: human, can: [author, propose] }
          - { name: agent, can: [propose] }
        lanes:
          - { name: knowledge, kind: canon }
          - { name: review,  kind: queue }
        entries: []
      YAML
      p2 = described_class.new(Textus::Manifest::Data.parse(raw2, root: "."))
      expect(p2.actor_for("propose")).to eq("human")
    end

    it "resolves by capability, not by a conventional name (agent may hold converge)" do
      raw2 = YAML.safe_load(<<~YAML, aliases: false)
        version: textus/3
        roles:
          - { name: agent, can: [propose, converge] }
        lanes:
          - { name: review, kind: queue }
          - { name: artifacts, kind: machine }
        entries: []
      YAML
      p2 = described_class.new(Textus::Manifest::Data.parse(raw2, root: "."))
      expect(p2.actor_for("converge")).to eq("agent")
    end

    it "returns nil when no role holds the verb" do
      raw2 = YAML.safe_load(<<~YAML, aliases: false)
        version: textus/3
        roles:
          - { name: human, can: [author, propose] }
        lanes:
          - { name: knowledge, kind: canon }
        entries: []
      YAML
      p2 = described_class.new(Textus::Manifest::Data.parse(raw2, root: "."))
      expect(p2.actor_for("converge")).to be_nil
    end
  end

  describe "#propose_lane_for" do
    context "when the role writes the declared kind: queue zone" do
      let(:yaml) do
        <<~YAML
          version: textus/3
          roles:
            - { name: human,      can: [author, propose] }
            - { name: automation, can: [converge] }
          lanes:
            - { name: review, kind: queue }
            - { name: draft,  kind: machine }
          entries:
            - { key: review.notes, path: review/notes.md, lane: review, owner: human:self, kind: leaf }
        YAML
      end

      it "returns that zone name" do
        expect(policy.propose_lane_for("human")).to eq("review")
      end
    end

    context "when no zone declares kind: queue" do
      it "returns nil (no substring fallback)" do
        raw2 = YAML.safe_load(<<~YAML, aliases: false)
          version: textus/3
          roles: [{ name: human, can: [author, propose] }]
          lanes: [{ name: review, kind: canon }]
          entries: []
        YAML
        p2 = described_class.new(Textus::Manifest::Data.parse(raw2, root: "."))
        expect(p2.propose_lane_for("human")).to be_nil
      end
    end

    context "when no queue lane is declared" do
      it "returns nil" do
        expect(policy.propose_lane_for("human")).to be_nil
      end
    end

    context "when the role is nil" do
      it "returns nil" do
        expect(policy.propose_lane_for(nil)).to be_nil
      end
    end

    context "when the role is unknown (not a writer of any zone)" do
      it "returns nil" do
        expect(policy.propose_lane_for("ghost")).to be_nil
      end
    end

    context "when the role writes multiple zones — a non-queue zone declared first, then the queue zone" do
      let(:yaml) do
        <<~YAML
          version: textus/3
          roles:
            - { name: human, can: [author, propose] }
          lanes:
            - { name: knowledge, kind: canon }
            - { name: review,  kind: queue }
          entries:
            - { key: knowledge.notes, path: knowledge/notes.md, lane: knowledge, owner: human:self, kind: leaf }
            - { key: review.notes,  path: review/notes.md,  lane: review,  owner: human:self, kind: leaf }
        YAML
      end

      it "returns the queue zone, skipping the non-queue zone declared first" do
        expect(policy.propose_lane_for("human")).to eq("review")
      end
    end
  end

  describe "zone-kind lookups" do
    let(:yaml) do
      <<~YAML
        version: textus/3
        roles:
          - { name: human,      can: [author, propose] }
          - { name: agent,      can: [propose] }
          - { name: automation, can: [converge] }
        lanes:
          - { name: knowledge, kind: canon }
          - { name: review,  kind: queue }
          - { name: artifacts,  kind: machine }
        entries: []
      YAML
    end

    it "returns the declared kind for a zone" do
      expect(policy.declared_kind("review")).to eq(:queue)
      expect(policy.declared_kind("knowledge")).to eq(:canon)
    end

    it "finds the queue zone by declared kind" do
      expect(policy.queue_lane).to eq("review")
    end

    it "treats a kind: machine zone as the generator zone (machine_lane)" do
      expect(policy.machine_lane).to eq("artifacts")
      expect(policy.declared_kind("knowledge")).not_to eq(:machine)
    end

    it "does NOT treat a non-machine zone as the machine zone" do
      raw2 = YAML.safe_load(<<~YAML, aliases: false)
        version: textus/3
        roles: [{ name: human, can: [author, propose] }]
        lanes: [{ name: out, kind: canon }]
        entries: []
      YAML
      p2 = described_class.new(Textus::Manifest::Data.parse(raw2, root: "."))
      expect(p2.machine_lane).to be_nil
    end

    it "lists author-holders via roles_with_capability" do
      expect(policy.roles_with_capability("author")).to eq(["human"])
    end
  end

  describe "#propose_lane_for with declared queue" do
    let(:yaml) do
      <<~YAML
        version: textus/3
        roles:
          - { name: human, can: [author, propose] }
          - { name: agent, can: [propose] }
        lanes:
          - { name: knowledge, kind: canon }
          - { name: inbox,   kind: queue }
        entries: []
      YAML
    end

    it "returns the kind: queue zone even when its name is not 'review'" do
      expect(policy.propose_lane_for("agent")).to eq("inbox")
    end

    it "returns the queue zone for any role that can write it, and nil for a non-writer" do
      expect(policy.propose_lane_for("human")).to eq("inbox")
      expect(policy.propose_lane_for("nobody")).to be_nil
    end
  end

  describe "declared zone kinds on Data" do
    let(:yaml) do
      <<~YAML
        version: textus/3
        roles:
          - { name: human,      can: [author, propose] }
          - { name: agent,      can: [propose] }
          - { name: automation, can: [converge] }
        lanes:
          - { name: knowledge, kind: canon }
          - { name: review,  kind: queue }
          - { name: artifacts,  kind: machine }
        entries: []
      YAML
    end

    it "exposes declared_lane_kinds keyed by zone name with symbol values" do
      expect(data.declared_lane_kinds).to eq(
        "knowledge" => :canon, "review" => :queue, "artifacts" => :machine,
      )
    end

    it "rejects a manifest whose zone declares no kind" do
      raw2 = YAML.safe_load("version: textus/3\nlanes:\n  - { name: w }\nentries: []\n", aliases: false)
      expect { Textus::Manifest::Data.parse(raw2, root: ".") }
        .to raise_error(Textus::BadManifest, /must declare a kind|is missing/)
    end
  end
end
