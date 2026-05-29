require "spec_helper"
require "fileutils"
require "tmpdir"

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
      FileUtils.mkdir_p(File.join(root, "zones/working/notes"))
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/3
        zones:
          - { name: working, write_policy: [human, agent, runner] }
        entries:
          - { key: working.notes, path: working/notes, zone: working, nested: true, kind: nested}
      YAML
      store.as("human").put("working.notes.alpha", meta: { "name" => "alpha" }, body: "hi")
    end

    it "dispatches a positional arg to the verb's use case (round-trip with Read::Get)" do
      direct = Textus::Read::Get.new(container: container, call: call).call("working.notes.alpha")
      via_invoke = described_class.invoke(
        :get, container: container, call: call, args: ["working.notes.alpha"]
      )

      expect(via_invoke.uid).to eq(direct.uid)
      expect(via_invoke.body).to eq(direct.body)
    end

    it "forwards kwargs to the verb's use case (Read::List#call(zone:))" do
      rows = described_class.invoke(
        :list, container: container, call: call, kwargs: { zone: "working" }
      )

      expect(rows.map { |r| r["key"] }).to include("working.notes.alpha")
      expect(rows).to all(include("zone" => "working"))
    end

    it "raises UsageError for an unknown verb (delegated through fetch)" do
      expect do
        described_class.invoke(:nonexistent_verb, container: container, call: call)
      end.to raise_error(Textus::UsageError)
    end
  end
end
