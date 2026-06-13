require "spec_helper"

RSpec.describe Textus::Dispatcher do
  it "exposes a frozen VERBS hash" do
    expect(described_class::VERBS).to be_frozen
    expect(described_class::VERBS).to be_a(Hash)
  end

  describe ".invoke" do
    include_context "textus_store_fixture"

    let(:store)     { Textus::Store.new(root) }
    let(:container) { fresh_container(store) }
    let(:call)      { test_ctx(role: "human") }

    before do
      FileUtils.mkdir_p(File.join(root, "data/knowledge/notes"))
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/3
        zones:
          - { name: knowledge, kind: canon }
        entries:
          - { key: knowledge.notes, path: knowledge/notes, zone: knowledge, kind: nested}
      YAML
      store.as("human").put("knowledge.notes.alpha", meta: { "name" => "alpha" }, body: "hi")
    end

    it "dispatches a positional arg to the verb's use case (round-trip with Read::Get pure)" do
      # Equivalence holds because the fixture key has no fetch rule, so the
      # read-through Read::Get degrades to a pure read — identical result.
      direct = Textus::Read::Get.new(container: container, call: call).call("knowledge.notes.alpha")
      via_invoke = described_class.invoke(
        :get, container: container, call: call, args: ["knowledge.notes.alpha"]
      )

      expect(via_invoke.uid).to eq(direct.uid)
      expect(via_invoke.body).to eq(direct.body)
    end

    it "forwards kwargs to the verb's use case (Read::List#call(zone:))" do
      rows = described_class.invoke(
        :list, container: container, call: call, kwargs: { zone: "knowledge" }
      )

      expect(rows.map { |r| r["key"] }).to include("knowledge.notes.alpha")
      expect(rows).to all(include("zone" => "knowledge"))
    end

    it "raises UsageError for an unknown verb (delegated through fetch)" do
      expect do
        described_class.invoke(:nonexistent_verb, container: container, call: call)
      end.to raise_error(Textus::UsageError)
    end
  end
end
