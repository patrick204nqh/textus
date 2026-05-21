require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe "Manifest source.action" do
  let(:tmp)  { Dir.mktmpdir }
  let(:root) { File.join(tmp, ".textus") }

  before { FileUtils.mkdir_p(root) }
  after  { FileUtils.remove_entry(tmp) }

  def write_manifest(yaml)
    File.write(File.join(root, "manifest.yaml"), yaml)
  end

  it "exposes ManifestEntry#action and #action_config" do
    write_manifest(<<~YAML)
      version: textus/1
      zones: [{ name: intake, writable_by: [script] }]
      entries:
        - key: intake.repos
          path: intake/repos.md
          zone: intake
          source: { action: github_repos, config: { org: acme }, ttl: 1h }
    YAML
    m = Textus::Manifest.load(root)
    e = m.entries.first
    expect(e.action).to eq("github_repos")
    expect(e.action_config).to eq({ "org" => "acme" })
    expect(e.ttl).to eq("1h")
  end

  it "exposes ManifestEntry#events from events: block" do
    write_manifest(<<~YAML)
      version: textus/1
      zones: [{ name: working, writable_by: [human] }]
      entries:
        - key: working.x
          path: working/x.md
          zone: working
          events:
            put:
              - { hook: notify }
    YAML
    m = Textus::Manifest.load(root)
    e = m.entries.first
    expect(e.events["put"].first["hook"]).to eq("notify")
  end

  context "events: block validation" do
    it "rejects unknown event names" do
      write_manifest(<<~YAML)
        version: textus/1
        zones: [{ name: working, writable_by: [human] }]
        entries:
          - key: working.x
            path: working/x.md
            zone: working
            events:
              nonsense:
                - { hook: notify }
      YAML
      expect { Textus::Manifest.load(root) }
        .to raise_error(Textus::UsageError, /unknown event 'nonsense'/)
    end

    it "accepts all five known events" do
      write_manifest(<<~YAML)
        version: textus/1
        zones: [{ name: working, writable_by: [human] }]
        entries:
          - key: working.x
            path: working/x.md
            zone: working
            events:
              put:     [{ hook: a }]
              delete:  [{ hook: b }]
              refresh: [{ hook: c }]
              build:   [{ hook: d }]
              accept:  [{ hook: e }]
      YAML
      expect { Textus::Manifest.load(root) }.not_to raise_error
    end
  end

  it "action_config defaults to {} when entry has no source block" do
    write_manifest(<<~YAML)
      version: textus/1
      zones: [{ name: working, writable_by: [human] }]
      entries:
        - { key: working.x, path: working/x.md, zone: working }
    YAML
    e = Textus::Manifest.load(root).entries.first
    expect(e.action).to be_nil
    expect(e.action_config).to eq({})
    expect(e.ttl).to be_nil
  end
end
