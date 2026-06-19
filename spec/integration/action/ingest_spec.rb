# frozen_string_literal: true

require "spec_helper"
require "fileutils"

RSpec.describe Textus::Action::Ingest do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, lanes: %w[raw notebook], manifest: <<~YAML)
      version: textus/4
      roles:
        - { name: human,      can: [author, propose] }
        - { name: agent,      can: [propose, keep, ingest] }
        - { name: automation, can: [converge] }
      lanes:
        - { name: raw,      kind: raw,       desc: "ingest log" }
        - { name: notebook, kind: workspace, desc: "agent notes" }
      entries:
        - { key: raw,            lane: raw,      owner: agent:self, nested: true, kind: nested, format: yaml }
        - { key: notebook.notes, lane: notebook, owner: agent:self, nested: true, kind: nested }
    YAML
  end

  describe "url kind" do
    it "writes a yaml raw entry with null body" do
      store.as("agent").ingest(
        kind: "url", slug: "github-pr-218",
        url: "https://github.com/org/repo/pull/218", label: "PR #218"
      )
      env = store.as("agent").get("raw.#{Time.now.utc.strftime("%Y.%m.%d")}.url-github-pr-218")
      expect(env).not_to be_nil
      expect(env.content["source"]["kind"]).to eq("url")
      expect(env.content["source"]["url"]).to eq("https://github.com/org/repo/pull/218")
      expect(env.body).to be_a(String)
    end

    it "raises on second ingest of the same slug on the same day (write-once)" do
      store.as("agent").ingest(kind: "url", slug: "pr-dupe", url: "https://example.com")
      expect do
        store.as("agent").ingest(kind: "url", slug: "pr-dupe", url: "https://example.com/2")
      end.to raise_error(Textus::Error, /already exists/)
    end
  end

  describe "file kind" do
    let(:tmp_file) do
      path = File.join(root, "tmp_plan.md")
      File.write(path, "# Sprint plan\n\nsome content")
      path
    end

    it "writes a markdown raw entry with file body" do
      store.as("agent").ingest(kind: "file", slug: "sprint-plan", path: tmp_file)
      date = Time.now.utc.strftime("%Y.%m.%d")
      env = store.as("agent").get("raw.#{date}.file-sprint-plan")
      expect(env).not_to be_nil
      expect(env.content["body"]).to include("Sprint plan")
      expect(env.content["source"]["kind"]).to eq("file")
    end
  end

  describe "asset kind" do
    let(:tmp_asset) do
      path = File.join(root, "screenshot.png")
      File.write(path, "PNG_BYTES")
      path
    end

    it "copies the asset file and writes a yaml entry with asset path" do
      store.as("agent").ingest(
        kind: "asset", slug: "login-screenshot",
        path: tmp_asset, zone: "playwright"
      )
      date = Time.now.utc.strftime("%Y.%m.%d")
      env = store.as("agent").get("raw.#{date}.asset-login-screenshot")
      expect(env).not_to be_nil
      expect(env.content["asset"]).to match(%r{raw/\d{4}/\d{2}/\d{2}/playwright/screenshot\.png})
      asset_path = File.join(root, "assets", env.content["asset"])
      expect(File.exist?(asset_path)).to be(true)
    end

    it "creates a .gitignore sentinel in .textus/assets/" do
      store.as("agent").ingest(
        kind: "asset", slug: "screenshot-2",
        path: tmp_asset, zone: "evidence"
      )
      gitignore = File.join(root, "assets", ".gitignore")
      expect(File.exist?(gitignore)).to be(true)
      expect(File.read(gitignore)).to eq("*\n")
    end
  end

  it "raises UsageError for an unknown kind" do
    expect do
      store.as("agent").ingest(kind: "ftp", slug: "bad")
    end.to raise_error(Textus::UsageError, /kind must be one of/)
  end

  it "raises UsageError when url kind is missing --url" do
    expect do
      store.as("agent").ingest(kind: "url", slug: "no-url")
    end.to raise_error(Textus::UsageError, /requires.*url/)
  end

  describe "dedup" do
    it "stores content_hash on first ingest" do
      store.as("agent").ingest(kind: "url", slug: "dedup-test", url: "https://example.com/dedup")
      date = Time.now.utc.strftime("%Y.%m.%d")
      env = store.as("agent").get("raw.#{date}.url-dedup-test")
      expect(env.content["content_hash"]).to match(/\Asha256:[a-f0-9]{64}\z/)
    end

    it "strips old entry to tombstone with superseded_by on alias" do
      unique_url = "https://unique.example.com/alias-#{SecureRandom.hex(4)}"
      date = Time.now.utc.strftime("%Y.%m.%d")

      store.as("agent").ingest(kind: "url", slug: "alias-a", url: unique_url)
      store.as("agent").ingest(kind: "url", slug: "alias-b", url: unique_url)

      env_a = store.as("agent").get("raw.#{date}.url-alias-a")
      expect(env_a.content["superseded_by"]).to eq("raw.#{date}.url-alias-b")
      expect(env_a.content["url"]).to be_nil
      expect(env_a.content["body"]).to be_nil
      expect(env_a.content["ingested_at"]).not_to be_nil
      expect(env_a.content.dig("source", "kind")).to eq("url")
    end

    it "new entry has supersedes and full content on alias" do
      unique_url = "https://unique.example.com/alias2-#{SecureRandom.hex(4)}"
      date = Time.now.utc.strftime("%Y.%m.%d")

      store.as("agent").ingest(kind: "url", slug: "alias-c", url: unique_url)
      env_c = store.as("agent").get("raw.#{date}.url-alias-c")
      hash_c = env_c.content["content_hash"]

      store.as("agent").ingest(kind: "url", slug: "alias-d", url: unique_url)
      env_d = store.as("agent").get("raw.#{date}.url-alias-d")
      expect(env_d.content["supersedes"]).to eq("raw.#{date}.url-alias-c")
      expect(env_d.content["source"]["url"]).to eq(unique_url)
      expect(env_d.content["content_hash"]).to eq(hash_c)
    end

    it "deduplicates by content hash for file kind with different slugs" do
      tmp_file_path = File.join(tmp, "same_content.txt")
      File.write(tmp_file_path, "identical body content for hash dedup")

      date = Time.now.utc.strftime("%Y.%m.%d")

      store.as("agent").ingest(kind: "file", slug: "first-name", path: tmp_file_path)
      store.as("agent").ingest(kind: "file", slug: "second-name", path: tmp_file_path)

      env1 = store.as("agent").get("raw.#{date}.file-first-name")
      expect(env1.content["superseded_by"]).to eq("raw.#{date}.file-second-name")
      expect(env1.content["body"]).to be_nil

      env2 = store.as("agent").get("raw.#{date}.file-second-name")
      expect(env2.content["supersedes"]).to eq("raw.#{date}.file-first-name")
      expect(env2.content["body"]).to eq("identical body content for hash dedup")
    end

    it "still rejects same-day same-slug collision" do
      store.as("agent").ingest(kind: "url", slug: "day-collision", url: "https://example.com/day1")
      expect do
        store.as("agent").ingest(kind: "url", slug: "day-collision", url: "https://example.com/day1")
      end.to raise_error(Textus::Error, /already exists/)
    end

    it "updates the SQLite index after supersede" do
      unique_url = "https://example.com/index-#{SecureRandom.hex(4)}"
      date = Time.now.utc.strftime("%Y.%m.%d")
      store.as("agent").ingest(kind: "url", slug: "index-a", url: unique_url)
      first_env = store.as("agent").get("raw.#{date}.url-index-a")
      hash = first_env.content["content_hash"]

      store_port = Textus::Ports::Store.new(root: root).setup!
      lookup = Textus::Index::Lookup.new(store: store_port)
      expect(lookup.find_by_hash(hash)).to eq("raw.#{date}.url-index-a")
      expect(lookup.find_by_url(unique_url)).to eq("raw.#{date}.url-index-a")
      store_port.close

      store.as("agent").ingest(kind: "url", slug: "index-b", url: unique_url)

      store_port = Textus::Ports::Store.new(root: root).setup!
      lookup = Textus::Index::Lookup.new(store: store_port)
      expect(lookup.find_by_hash(hash)).to eq("raw.#{date}.url-index-b")
      expect(lookup.find_by_url(unique_url)).to eq("raw.#{date}.url-index-b")
      store_port.close
    end

    it "moves asset file on supersede" do
      asset_path = File.join(tmp, "dedup_asset.png")
      File.write(asset_path, "ASSET_BYTES_DEDUP")

      date = Time.now.utc.strftime("%Y.%m.%d")
      store.as("agent").ingest(kind: "asset", slug: "dedup-a", path: asset_path, zone: "tests")
      env_a = store.as("agent").get("raw.#{date}.asset-dedup-a")

      old_asset_path = File.join(root, "assets", env_a.content["asset"])
      expect(File.exist?(old_asset_path)).to be(true)

      store.as("agent").ingest(kind: "asset", slug: "dedup-b", path: asset_path, zone: "tests")

      env_b = store.as("agent").get("raw.#{date}.asset-dedup-b")
      new_asset_path = File.join(root, "assets", env_b.content["asset"])
      expect(File.exist?(new_asset_path)).to be(true)

      env_a_stale = store.as("agent").get("raw.#{date}.asset-dedup-a")
      expect(env_a_stale.content["asset"]).to be_nil
      expect(env_a_stale.content["superseded_by"]).to eq("raw.#{date}.asset-dedup-b")
      expect(env_b.content["asset"]).to match(%r{raw/#{date.gsub(".", "/")}/tests/dedup_asset\.png})
    end

    it "does not create alias when content differs" do
      file_a = File.join(tmp, "content_a.txt")
      File.write(file_a, "content A")
      file_b = File.join(tmp, "content_b.txt")
      File.write(file_b, "content B")

      date = Time.now.utc.strftime("%Y.%m.%d")
      store.as("agent").ingest(kind: "file", slug: "different-a", path: file_a)
      store.as("agent").ingest(kind: "file", slug: "different-b", path: file_b)

      env_a = store.as("agent").get("raw.#{date}.file-different-a")
      env_b = store.as("agent").get("raw.#{date}.file-different-b")
      expect(env_a.content["superseded_by"]).to be_nil
      expect(env_b.content["supersedes"]).to be_nil
      expect(env_a.content["body"]).to eq("content A")
      expect(env_b.content["body"]).to eq("content B")
    end
  end
end
