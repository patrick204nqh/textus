require "spec_helper"

# Proves the dogfood authority_handler hook (ADR 0112): the authority-model
# reference (lanes / zones / roles) is PROJECTED from the live truth — the
# closed coordination vocabulary (Schema::Vocabulary::LANES) and this manifest's
# declared roles + zones — so the tables in docs/reference/authority.md cannot
# drift. Loaded through the real Loader and invoked through the RpcRegistry,
# the same surface every resolve_handler goes through at runtime.
RSpec.describe "authority_handler" do
  let(:events) { Textus::Hooks::EventBus.new }
  let(:rpc)    { Textus::Hooks::RpcRegistry.new }
  # The handler reaches .manifest (for roles/zones) and is invoked via .rpc.
  let(:manifest) do
    Textus::Manifest.parse(<<~YAML)
      version: textus/3
      roles:
        - { name: human,      can: [author, propose] }
        - { name: agent,      can: [propose, keep] }
        - { name: automation, can: [converge] }
      zones:
        - { name: knowledge, kind: canon,     desc: "the truth" }
        - { name: notebook,  kind: workspace, owner: agent, desc: "agent notes" }
        - { name: artifacts, kind: machine,   desc: "computed outputs" }
        - { name: proposals, kind: queue,     desc: "awaiting accept" }
      entries:
        - { key: knowledge.foo, path: knowledge/foo.md, zone: knowledge, kind: leaf }
    YAML
  end
  let(:caps) { Struct.new(:rpc, :manifest).new(rpc, manifest) }

  before do
    # Load just the one hook file in isolation (mirrors verb_registry_handler_spec).
    handler_path = File.expand_path("../../../.textus/hooks/authority_handler.rb", __dir__)
    Dir.mktmpdir do |dir|
      FileUtils.cp(handler_path, File.join(dir, "authority_handler.rb"))
      Textus::Hooks::Loader.new(events: events, rpc: rpc).load_dir(dir)
    end
  end

  def invoke = rpc.invoke(:resolve_handler, :authority, caps: caps, config: {}, args: [])

  it "registers an :authority resolve_handler" do
    expect(rpc.names(:resolve_handler)).to include(:authority)
  end

  it "projects the zone-kind↔capability bijection verbatim from Vocabulary::LANES" do
    lanes = invoke["content"]["lanes"].to_h { |r| [r["kind"], r["capability"]] }
    expect(lanes).to eq(Textus::Manifest::Schema::Vocabulary::LANES)
  end

  it "projects this manifest's zones with their derived capability" do
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
