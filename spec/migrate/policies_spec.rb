require "spec_helper"
require "tmpdir"
require "fileutils"
require "yaml"

RSpec.describe Textus::Migrate::Policies do
  let(:tmp) { Dir.mktmpdir }
  let(:root) { tmp }
  let(:manifest_path) { File.join(root, ".textus/manifest.yaml") }

  before { FileUtils.mkdir_p(File.join(root, ".textus")) }
  after { FileUtils.remove_entry(tmp) }

  it "hoists per-entry intake.ttl/on_stale into a top-level policies: block" do
    File.write(manifest_path, {
      "zones" => [{ "name" => "inbox", "writable_by" => ["script"] }],
      "entries" => [{
        "key" => "inbox.news.hn", "zone" => "inbox", "path" => "inbox/news/hn.md",
        "intake" => { "handler" => "http_get", "ttl" => "6h", "on_stale" => "refresh" }
      }],
    }.to_yaml)

    described_class.new(root: root).call

    yaml = YAML.load_file(manifest_path)
    intake = yaml["entries"][0]["intake"]
    expect(intake).not_to have_key("ttl")
    expect(intake).not_to have_key("on_stale")
    expect(intake["handler"]).to eq("http_get")
    expect(yaml["policies"]).to include(
      hash_including(
        "match" => "inbox.news.hn",
        "refresh" => hash_including("ttl" => "6h", "on_stale" => "refresh"),
      ),
    )
  end

  it "also hoists sync_budget_ms when present" do
    File.write(manifest_path, {
      "entries" => [{
        "key" => "inbox.news.hn", "zone" => "inbox", "path" => "inbox/news/hn.md",
        "intake" => { "handler" => "http_get", "ttl" => "6h", "sync_budget_ms" => 500 }
      }],
    }.to_yaml)
    described_class.new(root: root).call
    yaml = YAML.load_file(manifest_path)
    expect(yaml["policies"][0]["refresh"]).to include("sync_budget_ms" => 500, "ttl" => "6h")
    expect(yaml["entries"][0]["intake"]).not_to have_key("sync_budget_ms")
  end

  it "is idempotent — re-running produces no new blocks" do
    File.write(manifest_path, {
      "entries" => [{
        "key" => "inbox.news.hn", "zone" => "inbox", "path" => "inbox/news/hn.md",
        "intake" => { "handler" => "http_get", "ttl" => "6h", "on_stale" => "refresh" }
      }],
    }.to_yaml)
    described_class.new(root: root).call
    changes = described_class.new(root: root).call
    expect(changes).to be_empty
    yaml = YAML.load_file(manifest_path)
    expect(yaml["policies"].length).to eq(1)
  end

  it "leaves manifests with no entry-level ttl/on_stale untouched" do
    original = {
      "entries" => [{
        "key" => "inbox.news.hn", "zone" => "inbox", "path" => "inbox/news/hn.md",
        "intake" => { "handler" => "http_get" }
      }],
    }
    File.write(manifest_path, original.to_yaml)
    changes = described_class.new(root: root).call
    expect(changes).to be_empty
    expect(YAML.load_file(manifest_path)).to eq(original)
  end

  it "skips hoist if a policies block with same match already has a refresh rule" do
    File.write(manifest_path, {
      "entries" => [{
        "key" => "inbox.news.hn", "zone" => "inbox", "path" => "inbox/news/hn.md",
        "intake" => { "handler" => "http_get", "ttl" => "6h", "on_stale" => "refresh" }
      }],
      "policies" => [
        { "match" => "inbox.news.hn", "refresh" => { "ttl" => "1h", "on_stale" => "warn" } },
      ],
    }.to_yaml)

    changes = described_class.new(root: root).call
    expect(changes).to all(include(kind: :skip_existing))
    yaml = YAML.load_file(manifest_path)
    expect(yaml["policies"].length).to eq(1)
    expect(yaml["policies"][0]["refresh"]["ttl"]).to eq("1h")
    # entry-level fields preserved so the user can reconcile
    expect(yaml["entries"][0]["intake"]).to include("ttl" => "6h", "on_stale" => "refresh")
  end

  it "supports --dry-run: returns changes but does not write" do
    File.write(manifest_path, {
      "entries" => [{
        "key" => "inbox.news.hn", "zone" => "inbox", "path" => "inbox/news/hn.md",
        "intake" => { "handler" => "http_get", "ttl" => "6h" }
      }],
    }.to_yaml)
    original = File.read(manifest_path)
    changes = described_class.new(root: root, dry_run: true).call
    expect(changes).not_to be_empty
    expect(File.read(manifest_path)).to eq(original)
  end
end
