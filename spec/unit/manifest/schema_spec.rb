require "spec_helper"

RSpec.describe Textus::Manifest::Schema do
  def validate!(hash)
    described_class.validate!(hash)
  end

  it "accepts a minimal canonical manifest" do
    expect do
      validate!(
        "version" => "textus/3",
        "zones" => [{ "name" => "intake", "kind" => "machine" }],
        "entries" => [],
        "rules" => [],
      )
    end.not_to raise_error
  end

  it "rejects an unknown key at the root with path-prefixed message" do
    expect do
      validate!("version" => "textus/3", "zones" => [], "entries" => [], "garbage" => 1)
    end.to raise_error(Textus::BadManifest, /unknown key 'garbage' at '\$'/)
  end

  it "rejects an unknown key inside a zone (path includes index)" do
    expect do
      validate!(
        "version" => "textus/3",
        "zones" => [{ "name" => "intake", "kind" => "machine", "ohno" => 1 }],
        "entries" => [],
      )
    end.to raise_error(Textus::BadManifest, /unknown key 'ohno' at '\$\.zones\[0\]'/)
  end

  it "rejects writable_by (legacy alias) via the generic path" do
    expect do
      validate!(
        "version" => "textus/3",
        "zones" => [{ "name" => "intake", "kind" => "machine", "writable_by" => ["automation"] }],
        "entries" => [],
      )
    end.to raise_error(Textus::BadManifest, /unknown key 'writable_by'/)
  end

  it "rejects bare projection: at entry level via the generic path" do
    expect do
      validate!(
        "version" => "textus/3",
        "zones" => [{ "name" => "output", "kind" => "machine" }],
        "entries" => [{ "key" => "x", "zone" => "output", "path" => "x.json", "projection" => {} }],
      )
    end.to raise_error(Textus::BadManifest, /unknown key 'projection' at '\$\.entries\[0\]'/)
  end

  it "rejects an unknown source sub-key via the generic path" do
    expect do
      validate!(
        "version" => "textus/3",
        "zones" => [{ "name" => "output", "kind" => "machine" }],
        "entries" => [{
          "key" => "x", "zone" => "output", "path" => "x.json", "kind" => "derived",
          "source" => { "from" => "template", "template" => "t.mustache", "reduce" => "f" }
        }],
      )
    end.to raise_error(Textus::BadManifest, /unknown key 'reduce' at '\$\.entries\[0\]\.source'/)
  end

  it "rejects handler_allowlist in a rule via the generic path" do
    expect do
      validate!(
        "version" => "textus/3",
        "zones" => [{ "name" => "intake", "kind" => "machine" }],
        "entries" => [],
        "rules" => [{ "match" => "intake.x.*", "handler_allowlist" => ["h"] }],
      )
    end.to raise_error(Textus::BadManifest, /unknown key 'handler_allowlist' at '\$\.rules\[0\]'/)
  end

  it "rejects policies: at root via the generic path" do
    expect do
      validate!("version" => "textus/3", "zones" => [], "entries" => [], "policies" => [])
    end.to raise_error(Textus::BadManifest, /unknown key 'policies' at '\$'/)
  end

  def entry_manifest(extra)
    {
      "version" => "textus/3",
      "zones" => [{ "name" => "knowledge", "kind" => "canon" }],
      "entries" => [
        { "key" => "knowledge.skills", "path" => "knowledge/skills", "zone" => "knowledge",
          "kind" => "nested", "nested" => true }.merge(extra),
      ],
    }
  end

  describe "publish: target list (ADR 0094)" do
    it "accepts a list of to-targets" do
      expect { validate!(entry_manifest("publish" => [{ "to" => "A.md" }])) }.not_to raise_error
    end

    it "accepts a tree-target" do
      expect { validate!(entry_manifest("publish" => [{ "tree" => "skills" }])) }.not_to raise_error
    end

    it "rejects an unknown sub-key in a publish target" do
      expect { validate!(entry_manifest("publish" => [{ "bogus" => 1 }])) }
        .to raise_error(Textus::BadManifest, /unknown key 'bogus' at '\$\.entries\[0\]\.publish\[0\]'/)
    end

    it "rejects the retired map form" do
      expect { validate!(entry_manifest("publish" => { "to" => ["A.md"] })) }
        .to raise_error(Textus::BadManifest, /must be a list of targets|map form was retired/)
    end

    it "rejects a non-list publish value" do
      expect { validate!(entry_manifest("publish" => "CLAUDE.md")) }
        .to raise_error(Textus::BadManifest, /must be a list of targets/)
    end
  end

  it "accepts 'inbox' zone structurally (schema validates keys not values)" do
    # The schema walker validates KEYS, not values. An 'inbox' zone is structurally
    # legal here; nothing in the codebase actually creates zone directories under that name.
    # This is intentional — one error format per concern.
    expect do
      validate!(
        "version" => "textus/3",
        "zones" => [{ "name" => "inbox", "kind" => "machine" }],
        "entries" => [],
      )
    end.not_to raise_error
  end

  describe ".valid_owner? (#135)" do
    it "accepts a bare archetype (the shipped `owner: agent` zone form)" do
      expect(described_class.valid_owner?("agent")).to be(true)
      expect(described_class.valid_owner?("human")).to be(true)
      expect(described_class.valid_owner?("automation")).to be(true)
    end

    it "accepts <archetype>:<subject>" do
      expect(described_class.valid_owner?("human:patrick")).to be(true)
      expect(described_class.valid_owner?("agent:self")).to be(true)
      expect(described_class.valid_owner?("automation:ci")).to be(true)
    end

    it "rejects an archetype outside the closed set" do
      expect(described_class.valid_owner?("compiler:whoever")).to be(false)
      expect(described_class.valid_owner?("garbage")).to be(false)
    end

    it "rejects an empty subject" do
      expect(described_class.valid_owner?("human:")).to be(false)
    end

    it "rejects a subject containing a colon (PATTERN excludes ':')" do
      expect(described_class.valid_owner?("human:a:b")).to be(false)
    end

    it "rejects non-strings and the empty string" do
      expect(described_class.valid_owner?(nil)).to be(false)
      expect(described_class.valid_owner?("")).to be(false)
      expect(described_class.valid_owner?(42)).to be(false)
    end
  end

  describe "owner-subject validation (#135)" do
    it "accepts a bare archetype owner on a zone (shipped `owner: agent`)" do
      expect do
        validate!(
          "version" => "textus/3",
          # roles: present only so the workspace zone clears validate_zone_kind_consistency! (needs `keep`); unrelated to owner validation
          "roles" => [{ "name" => "agent", "can" => ["keep"] }],
          "zones" => [{ "name" => "notebook", "kind" => "workspace", "owner" => "agent" }],
          "entries" => [],
        )
      end.not_to raise_error
    end

    it "accepts <archetype>:<subject> on a zone and an entry" do
      expect do
        validate!(
          "version" => "textus/3",
          "zones" => [{ "name" => "knowledge", "kind" => "canon", "owner" => "human:self" }],
          "entries" => [{ "key" => "knowledge.identity", "path" => "knowledge/identity.md",
                          "zone" => "knowledge", "kind" => "leaf", "owner" => "human:self" }],
        )
      end.not_to raise_error
    end

    it "accepts a zone with no owner declared" do
      expect do
        validate!(
          "version" => "textus/3",
          "zones" => [{ "name" => "intake", "kind" => "machine" }],
          "entries" => [],
        )
      end.not_to raise_error
    end

    it "rejects an archetype outside the closed set, with a path-prefixed message" do
      expect do
        validate!(
          "version" => "textus/3",
          "zones" => [{ "name" => "z", "kind" => "canon", "owner" => "compiler:whoever" }],
          "entries" => [],
        )
      end.to raise_error(Textus::BadManifest, /invalid owner 'compiler:whoever' at '\$\.zones\[0\]'/)
    end

    it "rejects a garbage bare token" do
      expect do
        validate!(
          "version" => "textus/3",
          "zones" => [{ "name" => "z", "kind" => "canon", "owner" => "garbage" }],
          "entries" => [],
        )
      end.to raise_error(Textus::BadManifest, /invalid owner 'garbage'/)
    end

    it "rejects an empty subject on an entry, with the entry path" do
      expect do
        validate!(
          "version" => "textus/3",
          "zones" => [{ "name" => "z", "kind" => "canon" }],
          "entries" => [{ "key" => "z.x", "path" => "z/x.md", "zone" => "z",
                          "kind" => "leaf", "owner" => "human:" }],
        )
      end.to raise_error(Textus::BadManifest, /invalid owner 'human:' at '\$\.entries\[0\]'/)
    end

    it "rejects a non-string owner value" do
      expect do
        validate!(
          "version" => "textus/3",
          "zones" => [{ "name" => "z", "kind" => "canon", "owner" => 42 }],
          "entries" => [],
        )
      end.to raise_error(Textus::BadManifest, /invalid owner '42' at '\$\.zones\[0\]'/)
    end
  end

  it "rejects the retired upkeep rule key with a retention/source hint (ADR 0093)" do
    expect { Textus::Manifest::Schema.validate_rules!([{ "match" => "x.**", "upkeep" => { "on" => "stale", "ttl" => "30m" } }]) }
      .to raise_error(Textus::BadManifest, /`upkeep:` was removed.*retention/m)
  end

  describe "ADR 0091 machine kind" do
    it "accepts kind: machine and maps it to reconcile" do
      expect(Textus::Manifest::Schema::LANES["machine"]).to eq("reconcile")
      expect(Textus::Manifest::Schema::ZONE_KINDS).to contain_exactly("canon", "workspace", "machine", "queue")
    end

    it "rejects the retired quarantine/derived kinds with a 0091 hint" do
      expect do
        Textus::Manifest::Schema.validate_zones!([{ "name" => "feeds", "kind" => "quarantine" }])
      end.to raise_error(Textus::BadManifest, /folded into 'machine' \(ADR 0091\)/)
    end

    it "rejects a manifest with two machine zones" do
      raw = { "zones" => [
        { "name" => "artifacts", "kind" => "machine" },
        { "name" => "feeds", "kind" => "machine" },
      ] }
      expect { Textus::Manifest::Schema.validate_single_machine!(raw) }
        .to raise_error(Textus::BadManifest, /at most one zone may declare kind: machine/)
    end
  end
end
