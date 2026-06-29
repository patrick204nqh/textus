# frozen_string_literal: true

require "spec_helper"

RSpec.describe Textus::Doctor::Check::NotebookSources do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, lanes: %w[raw notebook], manifest: <<~YAML)
      version: textus/4
      roles:
        - { name: agent, can: [propose, keep, ingest] }
      lanes:
        - { name: raw,      kind: raw,       desc: "ingest log" }
        - { name: notebook, kind: workspace, desc: "notes" }
      entries:
        - { key: raw,            lane: raw,      owner: agent:self, nested: true, kind: nested, format: yaml }
        - { key: notebook.notes, lane: notebook, owner: agent:self, nested: true, kind: nested }
    YAML
  end

  it "returns no issues when all sources exist" do
    raw_path = File.join(root, "data/raw/2026/06/16/url-pr-1.yaml")
    FileUtils.mkdir_p(File.dirname(raw_path))
    File.write(raw_path, "ingested_at: '2026-06-16'\n")

    nb_path = File.join(root, "data/notebook/notes/pr-1.md")
    FileUtils.mkdir_p(File.dirname(nb_path))
    File.write(nb_path, "---\nsources:\n  - raw.2026.06.16.url-pr-1\n---\n\n")

    check = described_class.new(store.container)
    expect(check.call).to be_empty
  end

  it "warns when a notebook sources: key does not exist" do
    nb_path = File.join(root, "data/notebook/notes/orphan.md")
    FileUtils.mkdir_p(File.dirname(nb_path))
    File.write(nb_path, "---\nsources:\n  - raw.2026.06.16.url-gone\n---\n\n")

    check = described_class.new(store.container)
    issues = check.call
    expect(issues.length).to eq(1)
    expect(issues.first["code"]).to eq("notebook.source_missing")
    expect(issues.first["level"]).to eq("warning")
  end

  it "ignores notebook entries without sources" do
    nb_path = File.join(root, "data/notebook/notes/plain.md")
    FileUtils.mkdir_p(File.dirname(nb_path))
    File.write(nb_path, "# just a note\n")

    check = described_class.new(store.container)
    expect(check.call).to be_empty
  end
end
