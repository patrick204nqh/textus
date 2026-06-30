require "spec_helper"

RSpec.describe Textus::Links::Resolver do
  subject(:resolver) { described_class.new(manifest: manifest) }

  include_context "textus_store_fixture"

  let(:manifest) do
    store_from_manifest(root, lanes: %w[knowledge artifacts], manifest: <<~YAML).container.manifest
      version: textus/4
      roles:
        - { name: human,      can: [author] }
        - { name: automation, can: [converge] }
      lanes:
        - { name: knowledge, kind: canon }
        - { name: artifacts, kind: machine }
      entries:
        - { key: knowledge.goals.north-star, lane: knowledge, kind: leaf }
        - key: artifacts.reference.lanes
          lane: artifacts
          kind: produced
          format: json
          source: { from: external, command: "true", sources: [] }
          publish:
            - { to: docs/reference/lanes.md }
        - key: artifacts.how-to.agents-mcp
          lane: artifacts
          kind: produced
          format: json
          source: { from: external, command: "true", sources: [] }
          publish:
            - { to: docs/how-to/agents-mcp.md }
    YAML
  end

  describe "#resolve" do
    context "when target has a publish.to path" do
      it "returns a relative path from the source doc to the target doc" do
        result = resolver.resolve(
          key: "artifacts.reference.lanes",
          from_path: "docs/how-to/agents-mcp.md",
        )
        expect(result).to eq("../reference/lanes.md")
      end

      it "handles same-directory targets" do
        result = resolver.resolve(
          key: "artifacts.how-to.agents-mcp",
          from_path: "docs/how-to/configuring-lanes.md",
        )
        expect(result).to eq("agents-mcp.md")
      end

      it "handles targets at the root level" do
        result = resolver.resolve(
          key: "artifacts.reference.lanes",
          from_path: "README.md",
        )
        expect(result).to eq("docs/reference/lanes.md")
      end
    end

    context "when target has no publish.to path" do
      it "returns a textus get command string" do
        result = resolver.resolve(
          key: "knowledge.goals.north-star",
          from_path: "docs/how-to/agents-mcp.md",
        )
        expect(result).to eq("`textus get knowledge.goals.north-star`")
      end
    end

    context "when key does not exist in manifest" do
      it "raises UnknownKeyError" do
        expect do
          resolver.resolve(key: "artifacts.nonexistent", from_path: "docs/README.md")
        end.to raise_error(Textus::Links::Resolver::UnknownKeyError, /artifacts\.nonexistent/)
      end
    end
  end
end
