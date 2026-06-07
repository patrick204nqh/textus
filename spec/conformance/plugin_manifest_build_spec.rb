require "spec_helper"
require "json"

RSpec.describe "artifacts.claude-plugin build (ADR 0086)" do
  include_context "textus_store_fixture"

  let(:store) do
    FileUtils.mkdir_p(File.join(root, "zones/knowledge"))
    FileUtils.mkdir_p(File.join(root, "zones/artifacts"))
    FileUtils.mkdir_p(File.join(root, "hooks"))

    File.write(File.join(root, "hooks/plugin_manifest_reducer.rb"), <<~RUBY)
      Textus.hook do |reg|
        reg.on(:transform_rows, :plugin_manifest_reducer) do |rows:, **|
          project = rows.find { |r| r["_key"] == "knowledge.project" } || {}
          repo = project["repo"]
          command = { "type" => "command", "command" => "textus boot --lean" }
          session_start = %w[startup clear compact].map do |m|
            { "matcher" => m, "hooks" => [command] }
          end
          {
            "name" => project["name"] || "textus",
            "description" => "Durable, multi-writer repo memory for humans, agents, and automation. " \
                             "Auto-orients each session with a lean `textus boot` so the agent starts " \
                             "knowing the store's zones, write authority, and contract etag.",
            "version" => Textus::VERSION,
            "homepage" => repo,
            "repository" => repo,
            "license" => "MIT",
            "hooks" => { "SessionStart" => session_start },
            "mcpServers" => { "textus" => { "command" => "textus", "args" => %w[mcp serve] } },
          }
        end
      end
    RUBY

    s = store_from_manifest(root, zones: %w[knowledge artifacts], manifest: <<~YAML)
      version: textus/3
      zones:
        - { name: knowledge, kind: canon }
        - { name: artifacts, kind: machine }
      entries:
        - { key: knowledge.project, path: knowledge/project.md, zone: knowledge, kind: leaf }

        - key: artifacts.claude-plugin
          kind: produced
          path: artifacts/plugin.json
          zone: artifacts
          publish:
            - { to: .claude-plugin/plugin.json }
          source:
            from: project
            select:
              - knowledge.project
            transform: plugin_manifest_reducer
    YAML

    File.write(File.join(root, "zones/knowledge/project.md"),
               "---\nname: testproject\nrepo: https://example.com/testproject\n---\n")

    s
  end

  it "builds the in-store artifact with the expected plugin manifest structure" do
    store.as("automation").reconcile

    artifact_path = File.join(root, "zones/artifacts/plugin.json")
    expect(File.exist?(artifact_path)).to be true

    parsed = JSON.parse(File.read(artifact_path))
    expect(parsed["name"]).to eq("testproject")
    expect(parsed["version"]).to eq(Textus::VERSION)
    expect(parsed["license"]).to eq("MIT")
    expect(parsed["homepage"]).to eq("https://example.com/testproject")
    expect(parsed["repository"]).to eq("https://example.com/testproject")
  end

  it "publishes to .claude-plugin/plugin.json at the project root with no _meta key" do
    store.as("automation").reconcile

    published_path = File.join(tmp, ".claude-plugin", "plugin.json")
    expect(File.exist?(published_path)).to be true

    parsed = JSON.parse(File.read(published_path))
    expect(parsed.keys).to eq(%w[name description version homepage repository license hooks mcpServers])
    expect(parsed).not_to have_key("_meta")
    expect(parsed["version"]).to eq(Textus::VERSION)
  end

  it "includes the SessionStart hooks with startup, clear, compact matchers" do
    store.as("automation").reconcile

    published_path = File.join(tmp, ".claude-plugin", "plugin.json")
    parsed = JSON.parse(File.read(published_path))

    session_start = parsed.dig("hooks", "SessionStart")
    expect(session_start).to be_an(Array)
    expect(session_start.map { |g| g["matcher"] }).to eq(%w[startup clear compact])
    expect(session_start).to all(satisfy { |g| g.dig("hooks", 0, "command") == "textus boot --lean" })
  end

  it "includes the inline mcpServers stanza pointing to the installed binary" do
    store.as("automation").reconcile

    published_path = File.join(tmp, ".claude-plugin", "plugin.json")
    parsed = JSON.parse(File.read(published_path))

    expect(parsed.dig("mcpServers", "textus", "command")).to eq("textus")
    expect(parsed.dig("mcpServers", "textus", "args")).to eq(%w[mcp serve])
  end

  it "build is idempotent — repeated builds produce no content change" do
    store.as("automation").reconcile
    published_path = File.join(tmp, ".claude-plugin", "plugin.json")
    sha_first = Digest::SHA256.file(published_path).hexdigest

    store.as("automation").reconcile
    sha_second = Digest::SHA256.file(published_path).hexdigest

    expect(sha_second).to eq(sha_first)
  end
end
