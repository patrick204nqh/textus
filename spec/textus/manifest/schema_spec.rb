require "spec_helper"

RSpec.describe Textus::Manifest::Schema do
  def validate!(hash)
    described_class.validate!(hash)
  end

  it "accepts a minimal canonical manifest" do
    expect do
      validate!(
        "version" => "textus/3",
        "zones" => [{ "name" => "intake", "kind" => "quarantine", "read_policy" => ["all"] }],
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
        "zones" => [{ "name" => "intake", "kind" => "quarantine", "ohno" => 1 }],
        "entries" => [],
      )
    end.to raise_error(Textus::BadManifest, /unknown key 'ohno' at '\$\.zones\[0\]'/)
  end

  it "rejects writable_by (legacy alias) via the generic path" do
    expect do
      validate!(
        "version" => "textus/3",
        "zones" => [{ "name" => "intake", "kind" => "quarantine", "writable_by" => ["automation"] }],
        "entries" => [],
      )
    end.to raise_error(Textus::BadManifest, /unknown key 'writable_by'/)
  end

  it "rejects bare projection: at entry level via the generic path" do
    expect do
      validate!(
        "version" => "textus/3",
        "zones" => [{ "name" => "output", "kind" => "derived" }],
        "entries" => [{ "key" => "x", "zone" => "output", "path" => "x.json", "projection" => {} }],
      )
    end.to raise_error(Textus::BadManifest, /unknown key 'projection' at '\$\.entries\[0\]'/)
  end

  it "rejects compute.reduce via the generic path" do
    expect do
      validate!(
        "version" => "textus/3",
        "zones" => [{ "name" => "output", "kind" => "derived" }],
        "entries" => [{
          "key" => "x", "zone" => "output", "path" => "x.json",
          "compute" => { "kind" => "projection", "select" => ["w.x"], "reduce" => "f" }
        }],
      )
    end.to raise_error(Textus::BadManifest, /unknown key 'reduce' at '\$\.entries\[0\]\.compute'/)
  end

  it "rejects handler_allowlist in a rule via the generic path" do
    expect do
      validate!(
        "version" => "textus/3",
        "zones" => [{ "name" => "intake", "kind" => "quarantine" }],
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

  describe "fetch_timeout_seconds" do
    def manifest_with_timeout(value)
      {
        "version" => "textus/3",
        "zones" => [{ "name" => "intake", "kind" => "quarantine" }],
        "entries" => [],
        "rules" => [{ "match" => "intake.**", "fetch" => { "ttl" => "1h", "on_stale" => "warn", "fetch_timeout_seconds" => value } }],
      }
    end

    it "accepts a positive integer within the ceiling" do
      expect { validate!(manifest_with_timeout(600)) }.not_to raise_error
    end

    it "rejects values above the ceiling" do
      expect { validate!(manifest_with_timeout(60_000)) }
        .to raise_error(Textus::BadManifest, /fetch_timeout_seconds.*≤ 3600/)
    end

    it "rejects non-integer values" do
      expect { validate!(manifest_with_timeout("600")) }
        .to raise_error(Textus::BadManifest, /fetch_timeout_seconds.*positive integer/)
    end

    it "rejects zero or negative values" do
      expect { validate!(manifest_with_timeout(0)) }
        .to raise_error(Textus::BadManifest, /fetch_timeout_seconds.*positive integer/)
    end
  end

  it "accepts 'inbox' zone structurally (schema validates keys not values)" do
    # The schema walker validates KEYS, not values. The 'inbox' rename is gone
    # too — there is no special handling. An 'inbox' zone is structurally legal here;
    # nothing in the codebase actually creates zone directories under that name.
    # This is intentional — one error format per concern.
    expect do
      validate!(
        "version" => "textus/3",
        "zones" => [{ "name" => "inbox", "kind" => "quarantine" }],
        "entries" => [],
      )
    end.not_to raise_error
  end
end
