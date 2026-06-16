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
        - { key: knowledge.project, path: knowledge/project.md, lane: knowledge, kind: leaf }

        - key: artifacts.mcp-config
          kind: produced
          path: artifacts/mcp.json
          lane: artifacts
          source: { from: external, command: "make", sources: [] }
          publish:
            - { to: .mcp.json }
    YAML

    File.write(File.join(root, "data/knowledge/project.md"),
               "---\nname: testproject\ndescription: test\n---\n")

    s
  end

  it "converge_now does not raise (step-based transform replaced by workflow)" do
    expect { converge_now(store) }.not_to raise_error
  end
end
