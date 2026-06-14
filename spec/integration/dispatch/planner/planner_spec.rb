RSpec.describe Textus::Dispatch::Planner::Planner do
  subject(:planner) { described_class.new(container: store.container) }

  include_context "textus_store_fixture"

  let(:react_manifest) { <<~YAML }
    version: textus/3
    lanes:
      - { name: knowledge, kind: canon }
      - { name: feeds, kind: machine }
    entries:
      - { key: knowledge.a, path: knowledge/a.md, lane: knowledge, kind: leaf }
      - key: feeds.catalog
        kind: produced
        path: feeds/catalog.json
        lane: feeds
        source: { from: derive, select: "knowledge", pluck: [title] }
        publish:
          - { to: CATALOG.md, template: catalog.mustache }
    rules:
      - match: feeds.*
        react:
          on: ["entry.written"]
          do: materialize
  YAML

  let(:store) do
    store_from_manifest(root, lanes: %w[knowledge feeds], manifest: react_manifest,
                              files: { "templates/catalog.mustache" => "{{title}}" })
  end

  context "when manifest has react rules" do
    it "enqueues materialize for entry.written trigger matching a rule" do
      jobs = planner.plan(
        trigger: { "type" => "entry.written", "target" => "artifacts.derived.test" },
        role: Textus::Role::AUTOMATION,
      )
      expect(jobs.map(&:type)).to include("materialize")
    end

    it "returns empty array when trigger matches no rule" do
      jobs = planner.plan(
        trigger: { "type" => "unknown.trigger", "target" => "knowledge.foo" },
        role: Textus::Role::AUTOMATION,
      )
      expect(jobs).to be_empty
    end

    it "prefers rules over ACTIONS_BY_TRIGGER when react rules exist" do
      jobs = planner.plan(
        trigger: { "type" => "entry.written", "target" => "artifacts.derived.test" },
        role: Textus::Role::AUTOMATION,
      )
      expect(jobs).not_to be_empty
      expect(jobs.first).to be_a(Textus::Core::Jobs::Job)
    end
  end
end
