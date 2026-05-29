require "spec_helper"

RSpec.describe Textus::Manifest::Policy do
  subject(:policy) { described_class.new(data) }

  let(:yaml) do
    <<~YAML
      version: textus/3
      roles:
        - { name: human, kind: proposer }
        - { name: builder, kind: generator }
      zones:
        - { name: working, write_policy: [human] }
        - { name: review,  write_policy: [builder] }
      entries:
        - { key: working.notes, path: working/notes.md, zone: working, schema: null, owner: human:self, kind: leaf }
    YAML
  end
  let(:raw) { YAML.safe_load(yaml, aliases: false) }
  let(:data) { Textus::Manifest::Data.parse(raw, root: ".") }

  it "returns Domain::Permission for #permission_for" do
    expect(policy.permission_for("working")).to be_a(Textus::Domain::Permission)
  end

  it "memoises zone_kinds across calls" do
    a = policy.zone_kinds("working")
    b = policy.zone_kinds("working")
    expect(a).to be(b) # same object
  end

  it "raises UsageError on undeclared zone" do
    expect { policy.zone_writers("nope") }.to raise_error(Textus::UsageError)
  end

  it "exposes role_mapping, role_kind, roles_with_kind" do
    expect(policy.role_mapping).to eq("human" => :proposer, "builder" => :generator)
    expect(policy.role_kind("human")).to eq(:proposer)
    expect(policy.roles_with_kind(:generator)).to eq(["builder"])
  end

  describe "#propose_zone_for" do
    context "when the role writes a zone whose name contains 'review'" do
      let(:yaml) do
        <<~YAML
          version: textus/3
          roles:
            - { name: human, kind: proposer }
            - { name: builder, kind: generator }
          zones:
            - { name: review, write_policy: [human] }
            - { name: draft,  write_policy: [builder] }
          entries:
            - { key: review.notes, path: review/notes.md, zone: review, schema: null, owner: human:self, kind: leaf }
        YAML
      end

      it "returns that zone name" do
        expect(policy.propose_zone_for("human")).to eq("review")
      end

      it "matches a zone whose name contains 'review' as a substring (e.g. 'peer-review')" do
        peer_yaml = <<~YAML
          version: textus/3
          roles:
            - { name: human, kind: proposer }
            - { name: builder, kind: generator }
          zones:
            - { name: peer-review, write_policy: [human] }
            - { name: draft,       write_policy: [builder] }
          entries:
            - { key: peer-review.notes, path: peer-review/notes.md, zone: peer-review, schema: null, owner: human:self, kind: leaf }
        YAML
        peer_raw  = YAML.safe_load(peer_yaml, aliases: false)
        peer_data = Textus::Manifest::Data.parse(peer_raw, root: ".")
        expect(described_class.new(peer_data).propose_zone_for("human")).to eq("peer-review")
      end
    end

    context "when the role writes only non-review zones" do
      it "returns nil" do
        # default fixture: human writes 'working' (no 'review' substring)
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

    context "when the role writes multiple zones — a non-review zone declared first, then a review zone" do
      let(:yaml) do
        <<~YAML
          version: textus/3
          roles:
            - { name: human, kind: proposer }
            - { name: builder, kind: generator }
          zones:
            - { name: working, write_policy: [human] }
            - { name: review,  write_policy: [human] }
          entries:
            - { key: working.notes, path: working/notes.md, zone: working, schema: null, owner: human:self, kind: leaf }
            - { key: review.notes,  path: review/notes.md,  zone: review,  schema: null, owner: human:self, kind: leaf }
        YAML
      end

      it "returns the review zone, skipping the non-review zone declared first" do
        expect(policy.propose_zone_for("human")).to eq("review")
      end
    end
  end

  describe "declared zone kinds on Data" do
    let(:yaml) do
      <<~YAML
        version: textus/3
        roles:
          - { name: human,   kind: accept_authority }
          - { name: agent,   kind: proposer }
          - { name: builder, kind: generator }
        zones:
          - { name: working, kind: origin,  write_policy: [human] }
          - { name: review,  kind: queue,   write_policy: [agent, human] }
          - { name: output,  kind: derived, write_policy: [builder] }
        entries: []
      YAML
    end

    it "exposes declared_zone_kinds keyed by zone name with symbol values" do
      expect(data.declared_zone_kinds).to eq(
        "working" => :origin, "review" => :queue, "output" => :derived,
      )
    end

    it "maps an undeclared kind to nil" do
      raw2 = YAML.safe_load("version: textus/3\nzones:\n  - { name: w, write_policy: [human] }\nentries: []\n", aliases: false)
      expect(Textus::Manifest::Data.parse(raw2, root: ".").declared_zone_kinds).to eq("w" => nil)
    end
  end
end
