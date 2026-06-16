# frozen_string_literal: true

require "spec_helper"
require "fileutils"

RSpec.describe Textus::Action::Ingest do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, lanes: %w[raw notebook], manifest: <<~YAML)
      version: textus/3
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
      env = store.as("agent").get("raw.#{Date.today.strftime("%Y.%m.%d")}.url-github-pr-218")
      expect(env).not_to be_nil
      expect(env.content["source"]["kind"]).to eq("url")
      expect(env.content["source"]["url"]).to eq("https://github.com/org/repo/pull/218")
      expect(env.body).to be_a(String)
    end

    it "creates a notebook.notes stub wired to the raw key" do
      store.as("agent").ingest(
        kind: "url", slug: "github-pr-218",
        url: "https://github.com/org/repo/pull/218"
      )
      date = Date.today.strftime("%Y.%m.%d")
      nb = store.as("agent").get("notebook.notes.github-pr-218")
      expect(nb).not_to be_nil
      expect(nb.body).to include("raw.#{date}.url-github-pr-218")
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
      date = Date.today.strftime("%Y.%m.%d")
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
      date = Date.today.strftime("%Y.%m.%d")
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
end
