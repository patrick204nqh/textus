require "spec_helper"

BOOT_WRITE_FLOWS_BOOT_RB = File.expand_path("../../../lib/textus/boot.rb", __dir__)
BOOT_WRITE_FLOWS_SPEC_MD = File.expand_path("../../../SPEC.md", __dir__)

RSpec.describe "Boot write-flows — agent-facing write guidance" do
  # Guard: agent-facing write-flow guidance must never name a verb that the
  # dispatcher no longer registers (fetch/fetch_all removed in ADR 0079).
  describe "name no deleted verbs" do
    include_context "textus_store_fixture"

    before do
      FileUtils.mkdir_p(File.join(root, "zones/intake"))
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/3
        roles:
          - { name: human,      can: [author, propose] }
          - { name: automation, can: [converge] }
        zones:
          - { name: identity, kind: canon, desc: "human-only" }
          - { name: intake,   kind: machine }
      YAML
    end

    let(:store) { Textus::Store.new(root) }
    let(:automation_flow) { Textus::Boot.build(container: store.container)["write_flows"]["automation"] }

    it "the automation write-flow does not invoke 'textus fetch'" do
      expect(automation_flow).not_to include("textus fetch")
    end

    it "the automation write-flow points at drain for machine zone refresh" do
      expect(automation_flow).to include("textus drain")
    end
  end

  # Guard (ADR 0037): each write-flow template is keyed by a capability. If a
  # capability is renamed in the LANES table (Manifest::Schema), a stale template
  # key silently orphans — the verb just drops out of write_flows with no error.
  # This pins the template keys to the capability vocabulary so a rename fails here.
  describe "WRITE_FLOW_TEMPLATES keys track the capability vocabulary (ADR 0037)" do
    let(:template_keys) { Textus::Boot::WRITE_FLOW_TEMPLATES.keys.map(&:to_s).sort }
    let(:capabilities)  { Textus::Manifest::Schema::CAPABILITIES.map(&:to_s).sort }

    it "has a template for every capability and no template for a non-capability" do
      msg = "write-flow templates #{template_keys.inspect} != capabilities #{capabilities.inspect}"
      expect(template_keys).to eq(capabilities), msg
    end
  end

  # Guard (ADR 0034): write_flows name live zones, not retired instance names.
  describe "name live zones, not retired ones (ADR 0034)" do
    include_context "textus_store_fixture"

    let(:store) do
      store_from_manifest(root, zones: %w[knowledge notebook artifacts proposals],
                                manifest: <<~YAML)
                                  version: textus/3
                                  roles:
                                    - { name: human,      can: [author, propose] }
                                    - { name: agent,      can: [propose, keep] }
                                    - { name: automation, can: [converge] }
                                  zones:
                                    - { name: knowledge, kind: canon }
                                    - { name: notebook,  kind: workspace, owner: agent }
                                    - { name: artifacts, kind: machine }
                                    - { name: proposals, kind: queue }
                                  entries: []
                                YAML
    end

    let(:flows) { Textus::Boot.build(container: store.container)["write_flows"] }

    it "names the live canon zone in the author flow" do
      expect(flows["human"]).to include("knowledge")
      expect(flows["human"]).not_to include("identity")
      expect(flows["human"]).not_to include("working")
    end

    it "emits a notebook write-flow for the keep-holder (the 0.33 gap)" do
      expect(flows["agent"]).to include("notebook")
      expect(flows["agent"]).to include("no accept needed")
    end

    it "names the live queue and machine zone (ADR 0091: the two machine kinds merged into one)" do
      expect(flows["agent"]).to include("proposals.*")
      expect(flows["automation"]).to include("artifacts")
    end

    it "never emits a retired zone instance name" do
      # `intake` and `output` are retired zone instance names; `intake` is also a
      # valid entry-kind descriptor (ADR 0091) so match only zone-name patterns.
      # `review` and `output` are pure zone-name relics with no other valid use.
      expect(flows.values.join(" ")).not_to match(/\b(?:review|output)\b/)
      # Detect `intake` only when used as a zone name (e.g. "write to intake")
      # not as an entry-kind modifier ("intake artifacts").
      expect(flows.values.join(" ")).not_to match(/\bwrite.*\bintake\b|\bintake\s+zone\b/)
    end
  end

  # Guard (ADR 0037): the agent protocol template embeds prose refs like
  # "SPEC.md §8" / "§5". When SPEC is renumbered, those rot silently and agents
  # get pointed at the wrong section. Assert every referenced section heading
  # still exists.
  describe "boot.rb SPEC section refs resolve to real headings (ADR 0037)" do
    let(:referenced_sections) do
      File.read(BOOT_WRITE_FLOWS_BOOT_RB).scan(/SPEC\.md\s+§(\d+)/).flatten.uniq.sort_by(&:to_i)
    end
    let(:spec_headings) do
      File.readlines(BOOT_WRITE_FLOWS_SPEC_MD).filter_map { |l| l[/^##\s+(\d+)\./, 1] }
    end

    it "finds at least one SPEC ref (guard against a silent empty scan)" do
      expect(referenced_sections).not_to be_empty
    end

    it "every referenced §N has a matching '## N.' heading in SPEC.md" do
      missing = referenced_sections - spec_headings
      expect(missing).to be_empty,
                         "boot.rb references SPEC sections with no heading: " \
                         "#{missing.map { |n| "§#{n}" }.inspect}"
    end
  end
end
