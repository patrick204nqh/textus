require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe "Manifest source.fetcher" do
  let(:tmp)  { Dir.mktmpdir }
  let(:root) { File.join(tmp, ".textus") }

  before { FileUtils.mkdir_p(root) }
  after  { FileUtils.remove_entry(tmp) }

  def write_manifest(yaml)
    File.write(File.join(root, "manifest.yaml"), yaml)
  end

  it "exposes ManifestEntry#fetcher and #fetcher_config" do
    write_manifest(<<~YAML)
      version: textus/1
      zones: [{ name: intake, writable_by: [script] }]
      entries:
        - key: intake.repos
          path: intake/repos.md
          zone: intake
          source: { fetcher: github_repos, config: { org: acme }, ttl: 1h }
    YAML
    m = Textus::Manifest.load(root)
    e = m.entries.first
    expect(e.fetcher).to eq("github_repos")
    expect(e.fetcher_config).to eq({ "org" => "acme" })
    expect(e.ttl).to eq("1h")
  end

  it "rejects legacy source.parse with a clear error" do
    write_manifest(<<~YAML)
      version: textus/1
      zones: [{ name: intake, writable_by: [script] }]
      entries:
        - key: intake.x
          path: intake/x.md
          zone: intake
          source: { from: https://e.com, parse: json, ttl: 1h }
    YAML
    expect { Textus::Manifest.load(root) }
      .to raise_error(Textus::UsageError, /source\.parse.*0\.2.*source\.fetcher/i)
  end

  it "rejects legacy hooks: top-level key" do
    write_manifest(<<~YAML)
      version: textus/1
      zones: [{ name: working, writable_by: [human] }]
      entries:
        - key: working.x
          path: working/x.md
          zone: working
          hooks: { on_put: [{ run: x }] }
    YAML
    expect { Textus::Manifest.load(root) }
      .to raise_error(Textus::UsageError, /hooks.*renamed.*events.*0\.2/i)
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

  it "fetcher_config defaults to {} when entry has no source block" do
    write_manifest(<<~YAML)
      version: textus/1
      zones: [{ name: working, writable_by: [human] }]
      entries:
        - { key: working.x, path: working/x.md, zone: working }
    YAML
    e = Textus::Manifest.load(root).entries.first
    expect(e.fetcher).to be_nil
    expect(e.fetcher_config).to eq({})
    expect(e.ttl).to be_nil
  end
end
