# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Produce: command publish-or-staleness via mode resolution (ADR 0094)" do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, lanes: %w[artifacts],
                              manifest: <<~YAML,
                                version: textus/3
                                lanes: [{ name: artifacts, kind: machine }]
                                entries:
                                  - key: artifacts.bundle
                                    kind: produced
                                    path: artifacts/bundle.json
                                    lane: artifacts
                                    source: { from: external, command: "true", sources: ["src/*"] }
                                    publish: [{ to: dist/bundle.json }]
                                  - key: artifacts.signal
                                    kind: produced
                                    path: artifacts/signal.json
                                    lane: artifacts
                                    source: { from: external, command: "true", sources: ["src/*"] }
                              YAML
                              files: { "data/artifacts/bundle.json" => "{\"ok\":true}\n" })
  end

  let(:produce) { Textus::Produce::Engine.new(container: store.container, call: test_ctx(role: "automation")) }

  it "publishes a command entry's existing store bytes without running the command" do
    out = produce.run(["artifacts.bundle"])
    expect(out[:completed]).to include("artifacts.bundle")
    published = JSON.parse(File.read(File.join(tmp, "dist/bundle.json")))
    expect(published).to eq("ok" => true)
  end

  it "completes as a no-op for a command entry with no publish targets (Publish::None)" do
    out = produce.run(["artifacts.signal"])
    expect(out[:completed]).to include("artifacts.signal")
    expect(out[:failed]).to be_empty
  end
end
