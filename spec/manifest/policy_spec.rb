require "spec_helper"

RSpec.describe Textus::Manifest::Policy do
  subject(:policy) { described_class.new(data) }

  let(:yaml) do
    <<~YAML
      version: textus/3
      roles:
        - { name: human,      can: [accept, propose] }
        - { name: automation, can: [fetch, build] }
      zones:
        - { name: working, kind: canon }
        - { name: review,  kind: derived }
      entries:
        - { key: working.notes, path: working/notes.md, zone: working, schema: null, owner: human:self, kind: leaf }
    YAML
  end
  let(:raw) { YAML.safe_load(yaml, aliases: false) }
  let(:data) { Textus::Manifest::Data.parse(raw, root: ".") }

  it "returns Domain::Permission for #permission_for" do
    expect(policy.permission_for("working")).to be_a(Textus::Domain::Permission)
  end

  it "raises UsageError on undeclared zone" do
    expect { policy.zone_writers("nope") }.to raise_error(Textus::UsageError)
  end

  describe "#verb_for_zone" do
    it "maps each zone to the capability its kind requires" do
      expect(policy.verb_for_zone("working")).to eq("accept")
      expect(policy.verb_for_zone("review")).to eq("build")
    end
  end

  describe "#roles_with_capability" do
    it "lists roles holding a given verb" do
      expect(policy.roles_with_capability("accept")).to eq(["human"])
      expect(policy.roles_with_capability("propose")).to eq(["human"])
      expect(policy.roles_with_capability("build")).to eq(["automation"])
    end
  end

  describe "#zone_writers" do
    it "returns roles holding the verb the zone-kind requires" do
      # origin requires accept → human; derived requires build → automation
      expect(policy.zone_writers("working")).to eq(["human"])
      expect(policy.zone_writers("review")).to eq(["automation"])
    end
  end

  describe "#proposer_role" do
    it "prefers a non-accept proposer over an accept+propose role" do
      # default-style: human=[accept,propose], agent=[propose] → agent wins
      raw2 = YAML.safe_load(<<~YAML, aliases: false)
        version: textus/3
        roles:
          - { name: human, can: [accept, propose] }
          - { name: agent, can: [propose] }
        zones:
          - { name: working, kind: canon }
          - { name: review,  kind: queue }
        entries: []
      YAML
      p2 = described_class.new(Textus::Manifest::Data.parse(raw2, root: "."))
      expect(p2.proposer_role).to eq("agent")
    end

    it "falls back to the first proposer when the only proposer also holds accept" do
      raw2 = YAML.safe_load(<<~YAML, aliases: false)
        version: textus/3
        roles:
          - { name: owner, can: [accept, propose] }
        zones:
          - { name: working, kind: canon }
          - { name: review,  kind: queue }
        entries: []
      YAML
      p2 = described_class.new(Textus::Manifest::Data.parse(raw2, root: "."))
      expect(p2.proposer_role).to eq("owner")
    end

    it "returns nil when no role holds propose" do
      raw2 = YAML.safe_load(<<~YAML, aliases: false)
        version: textus/3
        roles:
          - { name: automation, can: [fetch, build] }
        zones:
          - { name: intake, kind: quarantine }
          - { name: output, kind: derived }
        entries: []
      YAML
      p2 = described_class.new(Textus::Manifest::Data.parse(raw2, root: "."))
      expect(p2.proposer_role).to be_nil
    end
  end

  describe "#propose_zone_for" do
    context "when the role writes the declared kind: queue zone" do
      let(:yaml) do
        <<~YAML
          version: textus/3
          roles:
            - { name: human,      can: [accept, propose] }
            - { name: automation, can: [fetch, build] }
          zones:
            - { name: review, kind: queue }
            - { name: draft,  kind: derived }
          entries:
            - { key: review.notes, path: review/notes.md, zone: review, schema: null, owner: human:self, kind: leaf }
        YAML
      end

      it "returns that zone name" do
        expect(policy.propose_zone_for("human")).to eq("review")
      end
    end

    context "when no zone declares kind: queue" do
      it "returns nil (no substring fallback)" do
        raw2 = YAML.safe_load(<<~YAML, aliases: false)
          version: textus/3
          roles: [{ name: human, can: [accept, propose] }]
          zones: [{ name: review, kind: canon }]
          entries: []
        YAML
        p2 = described_class.new(Textus::Manifest::Data.parse(raw2, root: "."))
        expect(p2.propose_zone_for("human")).to be_nil
      end
    end

    context "when the role writes only non-queue zones" do
      it "returns nil" do
        # default fixture: human writes 'working' (kind: canon), not a queue
        expect(policy.propose_zone_for("human")).to be_nil
      end
    end

    context "when the role is nil" do
      it "returns nil" do
        expect(policy.propose_zone_for(nil)).to be_nil
      end
    end

    context "when the role is unknown (not a writer of any zone)" do
      it "returns nil" do
        expect(policy.propose_zone_for("ghost")).to be_nil
      end
    end

    context "when the role writes multiple zones — a non-queue zone declared first, then the queue zone" do
      let(:yaml) do
        <<~YAML
          version: textus/3
          roles:
            - { name: human, can: [accept, propose] }
          zones:
            - { name: working, kind: canon }
            - { name: review,  kind: queue }
          entries:
            - { key: working.notes, path: working/notes.md, zone: working, schema: null, owner: human:self, kind: leaf }
            - { key: review.notes,  path: review/notes.md,  zone: review,  schema: null, owner: human:self, kind: leaf }
        YAML
      end

      it "returns the queue zone, skipping the non-queue zone declared first" do
        expect(policy.propose_zone_for("human")).to eq("review")
      end
    end
  end

  describe "zone-kind lookups" do
    let(:yaml) do
      <<~YAML
        version: textus/3
        roles:
          - { name: human,      can: [accept, propose] }
          - { name: agent,      can: [propose] }
          - { name: automation, can: [fetch, build] }
        zones:
          - { name: working, kind: canon }
          - { name: review,  kind: queue }
          - { name: output,  kind: derived }
        entries: []
      YAML
    end

    it "returns the declared kind for a zone" do
      expect(policy.declared_kind("review")).to eq(:queue)
      expect(policy.declared_kind("working")).to eq(:canon)
    end

    it "finds the queue zone by declared kind" do
      expect(policy.queue_zone).to eq("review")
    end

    it "treats a kind: derived zone as derived" do
      expect(policy.derived_zone?("output")).to be(true)
      expect(policy.derived_zone?("working")).to be(false)
    end

    it "does NOT treat a non-derived zone as derived" do
      raw2 = YAML.safe_load(<<~YAML, aliases: false)
        version: textus/3
        roles: [{ name: human, can: [accept, propose] }]
        zones: [{ name: out, kind: canon }]
        entries: []
      YAML
      p2 = described_class.new(Textus::Manifest::Data.parse(raw2, root: "."))
      expect(p2.derived_zone?("out")).to be(false)
    end

    it "lists accept-holders via roles_with_capability" do
      expect(policy.roles_with_capability("accept")).to eq(["human"])
    end
  end

  describe "#propose_zone_for with declared queue" do
    let(:yaml) do
      <<~YAML
        version: textus/3
        roles:
          - { name: human, can: [accept, propose] }
          - { name: agent, can: [propose] }
        zones:
          - { name: working, kind: canon }
          - { name: inbox,   kind: queue }
        entries: []
      YAML
    end

    it "returns the kind: queue zone even when its name is not 'review'" do
      expect(policy.propose_zone_for("agent")).to eq("inbox")
    end

    it "returns the queue zone for any role that can write it, and nil for a non-writer" do
      expect(policy.propose_zone_for("human")).to eq("inbox")
      expect(policy.propose_zone_for("nobody")).to be_nil
    end
  end

  it "Entry#in_generator_zone? delegates to derived_zone?" do
    raw2 = YAML.safe_load(<<~YAML, aliases: false)
      version: textus/3
      roles: [{ name: automation, can: [fetch, build] }]
      zones: [{ name: output, kind: derived }]
      entries:
        - { key: output.x, path: output/x.md, zone: output, schema: null, owner: automation:auto, kind: derived,
            compute: { kind: projection, select: [working.notes], pluck: "*" }, template: x.mustache }
    YAML
    d2 = Textus::Manifest::Data.parse(raw2, root: ".")
    entry = d2.entries.first
    expect(entry.in_generator_zone?(d2.policy)).to be(true)
  end

  describe "declared zone kinds on Data" do
    let(:yaml) do
      <<~YAML
        version: textus/3
        roles:
          - { name: human,      can: [accept, propose] }
          - { name: agent,      can: [propose] }
          - { name: automation, can: [fetch, build] }
        zones:
          - { name: working, kind: canon }
          - { name: review,  kind: queue }
          - { name: output,  kind: derived }
        entries: []
      YAML
    end

    it "exposes declared_zone_kinds keyed by zone name with symbol values" do
      expect(data.declared_zone_kinds).to eq(
        "working" => :canon, "review" => :queue, "output" => :derived,
      )
    end

    it "rejects a manifest whose zone declares no kind" do
      raw2 = YAML.safe_load("version: textus/3\nzones:\n  - { name: w }\nentries: []\n", aliases: false)
      expect { Textus::Manifest::Data.parse(raw2, root: ".") }
        .to raise_error(Textus::BadManifest, /must declare a kind/)
    end
  end
end
