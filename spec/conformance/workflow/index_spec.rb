# frozen_string_literal: true

require "spec_helper"

RSpec.describe "artifacts.system.index workflow" do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, lanes: %w[knowledge artifacts], files: {
                          "workflows/test_index.rb" => <<~RUBY,
                            Textus.workflow "store_index" do
                              match "artifacts.system.index"

                              step :build do |_, ctx|
                                container = ctx.container
                                rows = container.manifest.resolver.enumerate.filter_map do |row|
                                  path = row[:path]
                                  next unless path && File.exist?(path)
                                  mentry = row[:manifest_entry]
                                  etag   = Textus::Value::Etag.for_file(path)
                                  {
                                    "key"    => row[:key],
                                    "lane"   => mentry.lane,
                                    "schema" => mentry.schema,
                                    "owner"  => mentry.owner,
                                    "format" => mentry.format,
                                    "etag"   => etag,
                                  }
                                end
                                { "content" => { "entries" => rows, "generated_at" => Time.now.utc.iso8601 } }
                              end

                              publish
                            end
                          RUBY
                        }, manifest: <<~YAML)
                          version: textus/4
                          roles:
                            - { name: human,      can: [author] }
                            - { name: automation, can: [converge] }
                          lanes:
                            - { name: knowledge, kind: canon }
                            - { name: artifacts, kind: machine }
                          entries:
                            - { key: knowledge.project, lane: knowledge, owner: human:self, kind: leaf }
                            - key: artifacts.system.index
                              lane: artifacts
                              kind: produced
                              format: json
                              source: { from: external, command: "true", sources: [] }
                        YAML
  end

  before do
    store.with_role("human").put("knowledge.project",
                                 meta: { "description" => "test" }, body: "")
  end

  it "no longer generates the old system index workflow" do
    expect(File.exist?(File.join(root, "workflows", "system", "index.rb"))).to be(false)
  end

  it "drain produces artifacts.system.index with an entries array" do
    Textus::Produce::Engine.converge(
      container: store.container,
      call: Textus::Value::Call.build(role: "automation"),
      keys: ["artifacts.system.index"],
    )
    env = store.with_role("human").get("artifacts.system.index")
    expect(env).not_to be_nil
    expect(env.content).to include("entries", "generated_at")
    expect(env.content["entries"]).to be_an(Array)
  end

  it "each index entry has key, lane, format, etag" do
    Textus::Produce::Engine.converge(
      container: store.container,
      call: Textus::Value::Call.build(role: "automation"),
      keys: ["artifacts.system.index"],
    )
    env = store.with_role("human").get("artifacts.system.index")
    project_row = env.content["entries"].find { |r| r["key"] == "knowledge.project" }
    expect(project_row).to include("key", "lane", "format", "etag")
    expect(project_row["lane"]).to eq("knowledge")
  end
end
