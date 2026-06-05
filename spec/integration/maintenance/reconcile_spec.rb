require "spec_helper"

RSpec.describe Textus::Maintenance::Reconcile do
  it "is registered as a dispatcher verb and a RoleScope method" do
    expect(Textus::Dispatcher::VERBS).to include(:reconcile)
    expect(Textus::Dispatcher::VERBS[:reconcile]).to eq(described_class)
    expect(Textus::RoleScope.instance_methods).to include(:reconcile)
  end

  it "declares a contract surfaced on both CLI and MCP" do
    spec = described_class.contract
    expect(spec.verb).to eq(:reconcile)
    expect(spec.cli?).to be(true)
    expect(spec.mcp?).to be(true)
  end

  describe "#call lifecycle sweep" do
    include_context "textus_store_fixture"

    before do
      FileUtils.mkdir_p(File.join(root, "zones/review"))
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/3
        zones:
          - { name: review, kind: canon }
        entries:
          - { key: review.oncall, path: review/oncall.md, zone: review, kind: leaf }
        rules:
          - match: "review.*"
            lifecycle: { ttl: 30d, on_expire: drop }
      YAML
      leaf = File.join(root, "zones/review/oncall.md")
      File.write(leaf, "---\n_meta: {name: oncall, uid: aaaaaaaaaaaaaaaa}\n---\nbody\n")
      aged = Time.now - (40 * 86_400)
      File.utime(aged, aged, leaf)
      FileUtils.mkdir_p(audit_dir_path(root))
      File.write(audit_log_path(root), "")
    end

    let(:store) { Textus::Store.new(root) }

    def build_reconcile
      cv = Textus::Call.new(role: "human", correlation_id: "t", now: Time.now, dry_run: false)
      described_class.new(container: store.container, call: cv)
    end

    it "drops an aged drop-policy entry and reports it" do
      leaf = File.join(root, "zones/review/oncall.md")
      result = build_reconcile.call
      expect(result["ok"]).to be(true)
      expect(result["dropped"]).to include("review.oncall")
      expect(File.exist?(leaf)).to be(false)
    end

    it "dry-run previews would_drop without deleting" do
      leaf = File.join(root, "zones/review/oncall.md")
      result = build_reconcile.call(dry_run: true)
      expect(result["dry_run"]).to be(true)
      expect(result["would_drop"]).to include("review.oncall")
      expect(File.exist?(leaf)).to be(true)
    end

    it "scopes by prefix (non-matching prefix is a no-op)" do
      leaf = File.join(root, "zones/review/oncall.md")
      result = build_reconcile.call(prefix: "nonexistent")
      expect(result["dropped"]).to be_empty
      expect(File.exist?(leaf)).to be(true)
    end

    # WS4: reconcile reports sweep failures in its payload AND publishes a
    # :reconcile_failed event, mirroring reactive materialize's :materialize_failed.
    it "publishes :reconcile_failed (and keeps the payload) when a sweep action fails" do
      deleter = instance_double(Textus::Write::KeyDelete)
      allow(Textus::Write::KeyDelete).to receive(:new).and_return(deleter)
      allow(deleter).to receive(:call).and_raise(Textus::IoError.new("disk gone"))

      events = store.container.events
      allow(events).to receive(:publish).and_call_original

      result = build_reconcile.call

      expect(result["ok"]).to be(false)
      expect(result["failed"]).to include("key" => "review.oncall", "error" => "disk gone")
      expect(events).to have_received(:publish).with(
        :reconcile_failed,
        hash_including(failed: [{ "key" => "review.oncall", "error" => "disk gone" }]),
      )
    end
  end

  describe "Phase 1: materialization" do
    include_context "textus_store_fixture"

    # Fixture: a canon zone with source entries + a derived zone with one
    # projection entry. The manifest omits `roles:` so the default mapping
    # applies (automation => [ingest, reconcile]).
    let(:store) do
      FileUtils.mkdir_p(File.join(root, "zones/knowledge/people"))
      FileUtils.mkdir_p(File.join(root, "zones/artifacts"))
      FileUtils.mkdir_p(File.join(root, "templates"))
      s = store_from_manifest(root, zones: %w[knowledge artifacts], manifest: <<~YAML)
        version: textus/3
        zones:
          - { name: knowledge, kind: canon }
          - { name: artifacts, kind: derived }
        entries:
          - { key: knowledge.people, path: knowledge/people, zone: knowledge, owner: human:self, kind: nested }
          - key: artifacts.roster
            kind: derived
            path: artifacts/roster.md
            zone: artifacts
            owner: automation:auto
            compute: { kind: projection, select: knowledge.people, pluck: [name], sort_by: name }
            template: roster.mustache
      YAML
      File.write(File.join(root, "zones/knowledge/people/alice.md"), "---\nname: alice\n---\n")
      File.write(File.join(root, "templates/roster.mustache"), "{{#entries}}- {{name}}\n{{/entries}}")
      FileUtils.mkdir_p(audit_dir_path(root))
      File.write(audit_log_path(root), "")
      s
    end

    def build_reconcile_for_derived
      cv = Textus::Call.new(role: "human", correlation_id: "t", now: Time.now, dry_run: false)
      described_class.new(container: store.container, call: cv)
    end

    it "apply mode: result includes materialized key list" do
      result = build_reconcile_for_derived.call(dry_run: false)
      expect(result).to include("materialized")
      expect(result["materialized"]).to include("artifacts.roster")
    end

    it "apply mode: derived entry artifact is written to the store" do
      artifact_path = File.join(root, "zones/artifacts/roster.md")
      expect(File.exist?(artifact_path)).to be(false)
      build_reconcile_for_derived.call(dry_run: false)
      expect(File.exist?(artifact_path)).to be(true)
    end

    it "dry_run mode: result includes would_materialize with derived keys" do
      result = build_reconcile_for_derived.call(dry_run: true)
      expect(result).to include("would_materialize")
      expect(result["would_materialize"]).to be_an(Array)
      expect(result["would_materialize"]).to include("artifacts.roster")
    end

    it "dry_run mode: does NOT write the derived artifact" do
      artifact_path = File.join(root, "zones/artifacts/roster.md")
      allow(Textus::Maintenance::Materialize).to receive(:new).and_call_original
      build_reconcile_for_derived.call(dry_run: true)
      expect(Textus::Maintenance::Materialize).not_to have_received(:new)
      expect(File.exist?(artifact_path)).to be(false)
    end

    it "dry_run mode: would_materialize respects prefix filter" do
      result = build_reconcile_for_derived.call(dry_run: true, prefix: "artifacts")
      expect(result["would_materialize"]).to include("artifacts.roster")

      result_other = build_reconcile_for_derived.call(dry_run: true, prefix: "knowledge")
      expect(result_other["would_materialize"]).not_to include("artifacts.roster")
    end

    it "dry_run mode: would_materialize is empty when no derived entries in scope" do
      result = build_reconcile_for_derived.call(dry_run: true, prefix: "nonexistent")
      expect(result["would_materialize"]).to be_empty
    end

    it "apply mode: runs materialize + sweep under one shared maintenance lock" do
      lock = instance_double(Textus::Ports::BuildLock)
      allow(Textus::Ports::BuildLock).to receive(:new).and_return(lock)
      allow(lock).to receive(:acquire_or_raise).and_yield
      result = build_reconcile_for_derived.call(dry_run: false)
      expect(Textus::Ports::BuildLock).to have_received(:new).once
      expect(lock).to have_received(:acquire_or_raise).once
      expect(result).to include("materialized", "ok")
    end

    it "dry_run mode: does NOT acquire the maintenance lock" do
      allow(Textus::Ports::BuildLock).to receive(:new).and_call_original
      build_reconcile_for_derived.call(dry_run: true)
      expect(Textus::Ports::BuildLock).not_to have_received(:new)
    end
  end
end
