# frozen_string_literal: true

require "spec_helper"

RSpec.describe Textus::Doctor::Check::RawAssetPaths do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, lanes: %w[raw], manifest: <<~YAML)
      version: textus/3
      roles:
        - { name: agent, can: [propose, keep, ingest] }
      lanes:
        - { name: raw, kind: raw, desc: "ingest log" }
      entries:
        - { key: raw, lane: raw, owner: agent:self, nested: true, kind: nested, format: yaml }
    YAML
  end

  it "returns no issues when all raw asset paths exist" do
    asset_rel = "raw/2026/06/16/playwright/shot.png"
    asset_abs = File.join(root, "assets", asset_rel)
    FileUtils.mkdir_p(File.dirname(asset_abs))
    File.write(asset_abs, "PNG")

    path = File.join(root, "data/raw/2026/06/16/asset-shot.yaml")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "ingested_at: '2026-06-16T10:00:00Z'\nsource:\n  kind: asset\nasset: #{asset_rel}\n")

    check = described_class.new(store.container)
    expect(check.call).to be_empty
  end

  it "warns when a raw entry's asset path is missing" do
    path = File.join(root, "data/raw/2026/06/16/asset-missing.yaml")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "ingested_at: '2026-06-16T10:00:00Z'\nsource:\n  kind: asset\nasset: raw/2026/06/16/playwright/missing.png\n")

    check = described_class.new(store.container)
    issues = check.call
    expect(issues.length).to eq(1)
    expect(issues.first["code"]).to eq("raw_asset.missing_file")
    expect(issues.first["level"]).to eq("error")
  end
end
