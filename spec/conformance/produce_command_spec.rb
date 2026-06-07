# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Produce: command publish-or-staleness via mode resolution (ADR 0094)" do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, zones: %w[artifacts],
                              manifest: <<~YAML,
                                version: textus/3
                                zones: [{ name: artifacts, kind: machine }]
                                entries:
                                  - key: artifacts.bundle
                                    kind: produced
                                    path: artifacts/bundle.json
                                    zone: artifacts
                                    source: { from: command, command: "true", sources: ["src/*"] }
                                    publish: [{ to: dist/bundle.json }]
                                  - key: artifacts.signal
                                    kind: produced
                                    path: artifacts/signal.json
                                    zone: artifacts
                                    source: { from: command, command: "true", sources: ["src/*"] }
                              YAML
                              files: { "zones/artifacts/bundle.json" => "{\"ok\":true}\n" })
  end

  let(:produce) { Textus::Produce::Engine.new(container: store.container, call: test_ctx(role: "automation")) }

  it "publishes a command entry's existing store bytes without running the command" do
    out = produce.call(keys: ["artifacts.bundle"])
    expect(out[:produced]).to include("artifacts.bundle")
    # Published artifacts land at repo_root (parent of .textus), which is `tmp` in the fixture.
    # The plan's test used `root` (.textus dir) — corrected to `tmp` here.
    # verbatim_source re-serializes JSON to strip _meta; no _meta present means
    # pretty-printed output. Check structural equality rather than exact bytes.
    published = JSON.parse(File.read(File.join(tmp, "dist/bundle.json")))
    expect(published).to eq("ok" => true)
  end

  it "skips a command entry with no publish targets (Publish::None)" do
    out = produce.call(keys: ["artifacts.signal"])
    expect(out[:skipped]).to include("artifacts.signal")
  end
end
