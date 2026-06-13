# spec/conformance/steps/authority_handler_spec.rb
require "spec_helper"

# Proves the dogfood authority_handler step (ADR 0112): the authority-model
# reference (lanes / zones / roles) is PROJECTED from the live truth — the
# closed coordination vocabulary (Schema::Vocabulary::LANES) and this manifest's
# declared roles + zones — so the tables in docs/reference/authority.md cannot
# drift. Loaded through the real Loader and invoked through the RegistryStore,
# the same surface every fetch step goes through at runtime.
RSpec.describe "authority_handler" do
  let(:registry) { Textus::Step::RegistryStore.new }
  # The handler reaches .manifest (for roles/zones) and is invoked via .rpc.
  let(:manifest) do
    Textus::Manifest.parse(<<~YAML)
      version: textus/3
      roles:
        - { name: human,      can: [author, propose] }
        - { name: agent,      can: [propose, keep] }
        - { name: automation, can: [converge] }
      lanes:
        - { name: knowledge, kind: canon,     desc: "the truth" }
        - { name: notebook,  kind: workspace, owner: agent, desc: "agent notes" }
        - { name: artifacts, kind: machine,   desc: "computed outputs" }
        - { name: proposals, kind: queue,     desc: "awaiting accept" }
      entries:
        - { key: knowledge.foo, path: data/knowledge/foo.md, lane: knowledge, kind: leaf }
    YAML
  end
  let(:caps) { Struct.new(:rpc, :manifest).new(registry, manifest) }

  before do
    # Load just the one step file in isolation (mirrors verb_registry_handler_spec).
    handler_path = File.expand_path("../../../.textus/steps/fetch/authority.rb", __dir__)
    Dir.mktmpdir do |dir|
      steps_dir = File.join(dir, "steps")
      FileUtils.mkdir_p(File.join(steps_dir, "fetch"))
      FileUtils.cp(handler_path, File.join(steps_dir, "fetch", "authority.rb"))
      Textus::Step::Loader.new(registry: registry).load_dir(steps_dir)
    end
  end

  def invoke = registry.invoke(:fetch, :authority, caps: caps, config: {}, args: [])

  it "registers an :authority fetch handler" do
    expect(registry.names(:fetch)).to include(:authority)
  end

  it "projects the zone-kind↔capability bijection verbatim from Vocabulary::LANES" do
    lanes = invoke["content"]["lanes"].to_h { |r| [r["kind"], r["capability"]] }
    expect(lanes).to eq(Textus::Manifest::Schema::Vocabulary::LANES)
  end

  it "projects this manifest's lanes with their derived capability" do
    knowledge = invoke["content"]["zones"].find { |z| z["name"] == "knowledge" }
    expect(knowledge).to include(
      "kind" => "canon", "capability" => "author", "desc" => "the truth",
    )
    artifacts = invoke["content"]["zones"].find { |z| z["name"] == "artifacts" }
    expect(artifacts).to include("kind" => "machine", "capability" => "converge")
  end

  it "projects this manifest's roles with the zone-kinds each can write" do
    human = invoke["content"]["roles"].find { |r| r["name"] == "human" }
    expect(human["can"]).to eq(%w[author propose])
    expect(human["writes_kinds"]).to eq(%w[canon queue])

    automation = invoke["content"]["roles"].find { |r| r["name"] == "automation" }
    expect(automation["can"]).to eq(%w[converge])
    expect(automation["writes_kinds"]).to eq(%w[machine])
  end

  it "is deterministic across invocations" do
    first = invoke
    second = invoke
    expect(first).to eq(second)
  end
end
