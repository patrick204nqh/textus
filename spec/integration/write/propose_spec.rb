require "spec_helper"

RSpec.describe Textus::Write::Propose do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, zones: %w[knowledge notebook proposals artifacts], schemas: {
                          "project" => File.read(File.expand_path("../../../.textus/schemas/project.yaml", __dir__)),
                        }, manifest: <<~YAML)
                          version: textus/3
                          roles:
                            - { name: human,      can: [author, propose] }
                            - { name: agent,      can: [propose, keep] }
                            - { name: automation, can: [converge] }
                          zones:
                            - { name: knowledge, kind: canon }
                            - { name: notebook,  kind: workspace }
                            - { name: proposals, kind: queue }
                            - { name: artifacts, kind: machine }
                          entries:
                            - { key: knowledge.project, path: knowledge/project.md, zone: knowledge, schema: project, kind: leaf }
                            - { key: notebook.notes, path: notebook/notes, zone: notebook, kind: nested, nested: true }
                            - { key: proposals.notes, path: proposals/notes, zone: proposals, kind: nested, nested: true }
                            - { key: proposals.decisions, path: proposals/decisions, zone: proposals, kind: nested, nested: true }
                        YAML
  end

  it "prefixes the key with the role's propose_zone and writes there" do
    env = store.as("agent").propose("decisions.adopt-x", meta: { "name" => "adopt-x" }, body: "yes\n")
    expect(env.key).to eq("proposals.decisions.adopt-x")
    expect(env.uid).not_to be_nil
  end

  it "errors when the role cannot propose" do
    expect do
      store.as("automation").propose("decisions.x", meta: { "name" => "x" }, body: "n\n")
    end.to raise_error(Textus::Error, /propose/)
  end

  it "declares an MCP contract whose single view emits the full wire envelope (ADR 0069)" do
    expect(described_class.contract.verb).to eq(:propose)
    expect(described_class.contract.mcp?).to be(true)
    wire = { "uid" => "u", "etag" => "e", "key" => "proposals.x", "zone" => "proposals" }
    env = instance_double(Textus::Envelope, to_h_for_wire: wire)
    shaped = described_class.contract.view(:default).call(env, {})
    expect(shaped).to eq(wire)
  end
end
