require "spec_helper"

# Guard (ADR 0037): SPEC §9's hand-written pulse / agent_quickstart example JSON
# must stay a faithful snapshot of the live envelope key sets. The doc examples
# are extracted by anchored text and their key sets compared to reality.
SPEC_SNAPSHOT_MD = File.expand_path("../SPEC.md", __dir__)

RSpec.describe "SPEC §9 examples snapshot the live envelope keys (ADR 0037)" do
  include_context "textus_store_fixture"

  before do
    FileUtils.mkdir_p(root)
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      roles:
        - { name: human, can: [author, propose] }
        - { name: agent, can: [propose] }
      zones:
        - { name: working, kind: canon }
        - { name: review,  kind: queue }
      entries: []
    YAML
  end

  let(:store) { Textus::Store.new(root) }

  # Parsed JSON object from the first ```json fenced block after `anchor`.
  # Captures the whole fenced body (not brace-matched) so nested braces are safe.
  def json_block_after(anchor)
    text  = File.read(SPEC_SNAPSHOT_MD)
    start = text.index(anchor) or raise "anchor not found in SPEC.md: #{anchor.inspect}"
    block = text[start..].match(/```json\s*\n(.*?)\n```/m) or raise "no json block after #{anchor.inspect}"
    JSON.parse(block[1])
  end

  it "pulse example documents exactly the keys Read::Pulse#call returns" do
    live = store.as("human").pulse(since: 0).keys.sort
    documented = json_block_after("`textus pulse` output shape").keys.sort
    expect(documented).to eq(live),
                          "SPEC §9 pulse example keys #{documented.inspect} != live #{live.inspect}"
  end

  it "agent_quickstart example documents exactly the keys boot synthesizes" do
    live = store.as("human").boot["agent_quickstart"].keys.sort
    documented = json_block_after("`textus boot` envelope extras").fetch("agent_quickstart").keys.sort
    expect(documented).to eq(live),
                          "SPEC §9 agent_quickstart example keys #{documented.inspect} != live #{live.inspect}"
  end
end
