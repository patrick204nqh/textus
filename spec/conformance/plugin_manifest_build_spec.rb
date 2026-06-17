require "spec_helper"
require "json"

RSpec.describe "artifacts.claude-plugin build (ADR 0086)" do
  include_context "textus_store_fixture"

  let(:store) do
    FileUtils.mkdir_p(File.join(root, "data/knowledge"))
    FileUtils.mkdir_p(File.join(root, "data/artifacts"))
    FileUtils.mkdir_p(File.join(root, "steps/transform"))

    File.write(File.join(root, "steps/transform/plugin_manifest.rb"), <<~RUBY)
      Class.new(Textus::Step::Transform) do
        def call(rows:, config:, **)
          _ = config
          project = rows.find { |r| r["_key"] == "knowledge.project" } || {}
          repo = project["repo"]
          command = { "type" => "command", "command" => "textus boot" }
          session_start = %w[startup clear compact].map do |m|
            { "matcher" => m, "hooks" => [command] }
          end
          {
            "name" => project["name"] || "textus",
            "description" => "Durable, multi-writer repo memory for humans, agents, and automation. " \
                             "Auto-orients each session with `textus boot`.",
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

    s = store_from_manifest(root, lanes: %w[knowledge artifacts], manifest: <<~YAML)
      version: textus/4
      lanes:
        - { name: knowledge, kind: canon }
        - { name: artifacts, kind: machine }
      entries:
        - { key: knowledge.project, path: knowledge/project.md, lane: knowledge, kind: leaf }

        - key: artifacts.claude-plugin
          kind: produced
          path: artifacts/plugin.json
          lane: artifacts
          source: { from: external, command: "make", sources: [] }
          publish:
            - { to: .claude-plugin/plugin.json }
    YAML

    File.write(File.join(root, "data/knowledge/project.md"),
               "---\nname: testproject\nrepo: https://example.com/testproject\n---\n")

    s
  end

  it "converge_now does not raise (step-based transform replaced by workflow)" do
    expect { converge_now(store) }.not_to raise_error
  end
end
