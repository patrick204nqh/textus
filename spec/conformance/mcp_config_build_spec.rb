require "spec_helper"
require "json"

RSpec.describe "artifacts.mcp-config build (ADR 0086)" do
  include_context "textus_store_fixture"

  let(:store) do
    FileUtils.mkdir_p(File.join(root, "zones/knowledge"))
    FileUtils.mkdir_p(File.join(root, "zones/artifacts"))
    FileUtils.mkdir_p(File.join(root, "hooks"))

    File.write(File.join(root, "hooks/mcp_config_reducer.rb"), <<~RUBY)
      Textus.hook do |reg|
        reg.on(:transform_rows, :mcp_config_reducer) do |**|
          {
            "mcpServers" => {
              "textus" => {
                "command" => "bundle",
                "args" => ["exec", "exe/textus", "--root", ".textus", "mcp", "serve"],
              },
            },
          }
        end
      end
    RUBY

    s = store_from_manifest(root, zones: %w[knowledge artifacts], manifest: <<~YAML)
      version: textus/3
      zones:
        - { name: knowledge, kind: canon }
        - { name: artifacts, kind: derived }
      entries:
        - { key: knowledge.project, path: knowledge/project.md, zone: knowledge, kind: leaf }

        - key: artifacts.mcp-config
          kind: derived
          path: artifacts/mcp.json
          zone: artifacts
          provenance: false
          publish:
            to:
              - .mcp.json
          compute:
            kind: projection
            select:
              - knowledge.project
            transform: mcp_config_reducer
    YAML

    File.write(File.join(root, "zones/knowledge/project.md"),
               "---\nname: testproject\ndescription: test\n---\n")

    s
  end

  it "builds the in-store artifact with the expected MCP server config" do
    store.as("automation").build

    artifact_path = File.join(root, "zones/artifacts/mcp.json")
    expect(File.exist?(artifact_path)).to be true

    parsed = JSON.parse(File.read(artifact_path))
    expect(parsed).to eq(
      "mcpServers" => {
        "textus" => {
          "command" => "bundle",
          "args" => ["exec", "exe/textus", "--root", ".textus", "mcp", "serve"],
        },
      },
    )
  end

  it "publishes to .mcp.json at the project root with no _meta key" do
    store.as("automation").build

    published_path = File.join(tmp, ".mcp.json")
    expect(File.exist?(published_path)).to be true

    parsed = JSON.parse(File.read(published_path))
    expect(parsed.keys).to eq(["mcpServers"])
    expect(parsed).not_to have_key("_meta")
    expect(parsed.dig("mcpServers", "textus", "command")).to eq("bundle")
    expect(parsed.dig("mcpServers", "textus", "args")).to eq(
      ["exec", "exe/textus", "--root", ".textus", "mcp", "serve"],
    )
  end

  it "build is idempotent — repeated builds produce no content change" do
    store.as("automation").build
    published_path = File.join(tmp, ".mcp.json")
    sha_first = Digest::SHA256.file(published_path).hexdigest

    store.as("automation").build
    sha_second = Digest::SHA256.file(published_path).hexdigest

    expect(sha_second).to eq(sha_first)
  end
end
