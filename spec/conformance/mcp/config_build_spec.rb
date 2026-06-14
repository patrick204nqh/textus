require "spec_helper"
require "json"

RSpec.describe "artifacts.mcp-config build (ADR 0086)" do
  include_context "textus_store_fixture"

  let(:store) do
    FileUtils.mkdir_p(File.join(root, "data/knowledge"))
    FileUtils.mkdir_p(File.join(root, "data/artifacts"))
    FileUtils.mkdir_p(File.join(root, "steps/transform"))

    File.write(File.join(root, "steps/transform/mcp_config_reducer.rb"), <<~RUBY)
      class McpConfigReducerTransform < Textus::Step::Transform
        def call(**)
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

    s = store_from_manifest(root, lanes: %w[knowledge artifacts], manifest: <<~YAML)
      version: textus/3
      lanes:
        - { name: knowledge, kind: canon }
        - { name: artifacts, kind: machine }
      entries:
        - { key: knowledge.project, path: data/knowledge/project.md, lane: knowledge, kind: leaf }

        - key: artifacts.mcp-config
          kind: produced
          path: data/artifacts/mcp.json
          lane: artifacts
          publish:
            - { to: .mcp.json }
          source:
            from: derive
            select:
              - knowledge.project
            transform: mcp_config_reducer
    YAML

    File.write(File.join(root, "data/knowledge/project.md"),
               "---\nname: testproject\ndescription: test\n---\n")

    s
  end

  it "builds the in-store artifact with the expected MCP server config" do
    converge_now(store)

    artifact_path = File.join(root, "data/artifacts/mcp.json")
    expect(File.exist?(artifact_path)).to be true

    # The STORED artifact is data and carries textus's _meta (ADR 0094);
    # only the published file is cleaned of it.
    parsed = JSON.parse(File.read(artifact_path))
    expect(parsed).to have_key("_meta")
    expect(parsed["mcpServers"]).to eq(
      "textus" => {
        "command" => "bundle",
        "args" => ["exec", "exe/textus", "--root", ".textus", "mcp", "serve"],
      },
    )
  end

  it "publishes to .mcp.json at the project root with no _meta key" do
    converge_now(store)

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
    converge_now(store)
    published_path = File.join(tmp, ".mcp.json")
    sha_first = Digest::SHA256.file(published_path).hexdigest

    converge_now(store)
    sha_second = Digest::SHA256.file(published_path).hexdigest

    expect(sha_second).to eq(sha_first)
  end
end
