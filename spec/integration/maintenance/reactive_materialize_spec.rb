require "spec_helper"

RSpec.describe Textus::Maintenance::ReactiveMaterialize do
  subject(:reactive) { described_class.new(container: store.container) }

  include_context "textus_store_fixture"

  let(:call) { test_ctx(role: "automation") }
  # The default fan-out is async (a fire-and-forget Thread). For deterministic
  # assertions on the inline effect, examples that need it use the sync fixture.
  let(:store) { build_store(materialize_on_change: "sync") }

  # Fixture: a canon zone (knowledge) holding a nested `knowledge.people` source,
  # plus a derived zone (artifacts) with a projection `artifacts.catalogs.people`
  # that selects `knowledge.people`. `materialize_on_change:` is interpolated into
  # an optional rule so individual examples can flip sync/async.
  def build_store(materialize_on_change: nil)
    FileUtils.mkdir_p(File.join(root, "zones/knowledge/people"))
    FileUtils.mkdir_p(File.join(root, "zones/artifacts"))
    FileUtils.mkdir_p(File.join(root, "templates"))
    rules = if materialize_on_change
              <<~RULES
                rules:
                  - match: "artifacts.catalogs.people"
                    upkeep: { strategy: #{materialize_on_change} }
              RULES
            else
              ""
            end
    s = store_from_manifest(root, zones: %w[knowledge artifacts], manifest: <<~YAML)
      version: textus/3
      zones:
        - { name: knowledge, kind: canon }
        - { name: artifacts, kind: machine }
      entries:
        - { key: knowledge.people, path: knowledge/people, zone: knowledge, owner: human:self, kind: nested }

        - key: artifacts.catalogs.people
          kind: derived
          path: artifacts/catalogs/people.md
          zone: artifacts
          owner: automation:auto
          compute: { kind: projection, select: knowledge.people, pluck: [name, org], sort_by: name }
          template: people.mustache
          publish:
            to: [PEOPLE.md]
      #{rules}
    YAML
    File.write(File.join(root, "zones/knowledge/people/alice.md"), "---\nname: alice\norg: x\n---\n")
    File.write(File.join(root, "templates/people.mustache"),
               "{{#entries}}- {{name}} ({{org}})\n{{/entries}}")
    s
  end

  # The derived artifact + its published leaf. `root` is the .textus dir; the
  # publish target (PEOPLE.md) lands in the repo root (its parent).
  def artifact_path  = File.join(root, "zones/artifacts/catalogs/people.md")
  def published_path = File.join(File.dirname(root), "PEOPLE.md")

  describe "impact set fan-out" do
    it "materializes the rdeps∩derived set for a canon source write" do
      reactive.on_write(key: "knowledge.people", call: call)

      expect(File).to exist(artifact_path)
      expect(File.read(artifact_path)).to include("alice")
      expect(File).to exist(published_path)
    end

    it "delegates exactly the impact set to Materialize" do
      mat = instance_double(Textus::Maintenance::Materialize)
      allow(Textus::Maintenance::Materialize).to receive(:new).and_return(mat)
      allow(mat).to receive(:call).and_return({})

      reactive.on_write(key: "knowledge.people", call: call)

      expect(mat).to have_received(:call).with(keys: ["artifacts.catalogs.people"])
    end

    it "does nothing when the write has no derived dependents" do
      allow(Textus::Maintenance::Materialize).to receive(:new)
      reactive.on_write(key: "knowledge.orphan", call: call)
      expect(Textus::Maintenance::Materialize).not_to have_received(:new)
    end
  end

  describe "recursion guard" do
    it "does not fan out for a write into a derived-kind zone" do
      allow(Textus::Maintenance::Materialize).to receive(:new)
      reactive.on_write(key: "artifacts.catalogs.people", call: call)
      expect(Textus::Maintenance::Materialize).not_to have_received(:new)
    end
  end

  describe "sync vs async dispatch" do
    context "when an affected entry resolves materialize.on_change == sync" do
      it "materializes inline (artifact fresh on return) and does not enqueue async" do
        allow(Textus::Maintenance::ReactiveMaterialize::AsyncRunner).to receive(:enqueue)

        reactive.on_write(key: "knowledge.people", call: call)

        expect(Textus::Maintenance::ReactiveMaterialize::AsyncRunner).not_to have_received(:enqueue)
        expect(File).to exist(artifact_path)
        expect(File.read(artifact_path)).to include("alice")
      end
    end

    context "when no affected entry is sync (async default)" do
      let(:store) { build_store } # no materialize rule → async default

      it "chooses the async path via AsyncRunner.enqueue" do
        allow(Textus::Maintenance::ReactiveMaterialize::AsyncRunner).to receive(:enqueue)

        reactive.on_write(key: "knowledge.people", call: call)

        expect(Textus::Maintenance::ReactiveMaterialize::AsyncRunner)
          .to have_received(:enqueue)
          .with(container: store.container, call: call, keys: ["artifacts.catalogs.people"])
      end
    end
  end

  describe "failure isolation (ADR 0087 §5)" do
    let(:store) { build_store(materialize_on_change: "sync") } # force the inline path

    it "does not raise and publishes :materialize_failed when Materialize errors" do
      mat = instance_double(Textus::Maintenance::Materialize)
      allow(Textus::Maintenance::Materialize).to receive(:new).and_return(mat)
      allow(mat).to receive(:call).and_raise(Textus::IoError.new("boom"))

      events = store.container.events
      allow(events).to receive(:publish).and_call_original

      expect { reactive.on_write(key: "knowledge.people", call: call) }.not_to raise_error

      expect(events).to have_received(:publish).with(
        :materialize_failed, hash_including(keys: ["artifacts.catalogs.people"], error: "boom")
      )
    end

    it "soft-misses (no raise, no failure event) when the build lock is held" do
      allow(Textus::Ports::BuildLock).to receive(:with).and_raise(Textus::BuildInProgress.new("held"))

      events = store.container.events
      allow(events).to receive(:publish).and_call_original

      expect { reactive.on_write(key: "knowledge.people", call: call) }.not_to raise_error

      expect(events).not_to have_received(:publish).with(:materialize_failed, anything)
    end
  end
end
