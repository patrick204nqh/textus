require "spec_helper"

RSpec.describe Textus::Maintenance::Materialize do
  subject(:svc) do
    described_class.new(container: store.container, call: call)
  end

  include_context "textus_store_fixture"

  # Minimal fixture: a derived entry (projection) + a nested publish_tree entry.
  let(:store) do
    FileUtils.mkdir_p(File.join(root, "zones/knowledge/people"))
    FileUtils.mkdir_p(File.join(root, "zones/knowledge/agents"))
    FileUtils.mkdir_p(File.join(root, "zones/artifacts"))
    FileUtils.mkdir_p(File.join(root, "templates"))
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

        - key: knowledge.agents
          kind: nested
          path: knowledge/agents
          zone: knowledge
          owner: human:self
          publish:
            tree: "agents"
    YAML
    File.write(File.join(root, "zones/knowledge/people/alice.md"), "---\nname: alice\norg: x\n---\n")
    File.write(File.join(root, "zones/knowledge/people/bob.md"),   "---\nname: bob\norg: y\n---\n")
    File.write(File.join(root, "templates/people.mustache"),
               "{{#entries}}- {{name}} ({{org}})\n{{/entries}}")
    File.write(File.join(root, "zones/knowledge/agents/claude.md"), "---\nname: claude\n---\nbody\n")
    s
  end

  let(:call) { test_ctx(role: "automation") }

  describe "#call with no filters" do
    it "returns a hash with the expected envelope keys" do
      result = svc.call
      expect(result).to include("protocol", "built", "published_leaves", "pruned")
    end

    it "protocol matches Textus::PROTOCOL" do
      expect(svc.call["protocol"]).to eq(Textus::PROTOCOL)
    end

    it "includes the derived entry in built" do
      result = svc.call
      built_keys = result["built"].map { |b| b["key"] }
      expect(built_keys).to include("artifacts.catalogs.people")
    end

    it "includes the nested publish_tree entry in published_leaves" do
      result = svc.call
      leaf_keys = result["published_leaves"].map { |r| r["key"] }
      expect(leaf_keys).to include("knowledge.agents")
    end

    it "pruned is an Array" do
      expect(svc.call["pruned"]).to be_an(Array)
    end
  end

  describe "#call(prefix:)" do
    it "scopes built entries to the given prefix" do
      result = svc.call(prefix: "artifacts")
      built_keys = result["built"].map { |b| b["key"] }
      expect(built_keys).to include("artifacts.catalogs.people")
      # knowledge.agents is outside the prefix; should not appear in published_leaves
      leaf_keys = result["published_leaves"].map { |r| r["key"] }
      expect(leaf_keys).not_to include("knowledge.agents")
    end

    it "returns empty built + leaves when prefix matches nothing" do
      result = svc.call(prefix: "nonexistent.prefix")
      expect(result["built"]).to be_empty
      expect(result["published_leaves"]).to be_empty
    end

    it "includes the nested tree entry when prefix matches it" do
      result = svc.call(prefix: "knowledge")
      leaf_keys = result["published_leaves"].map { |r| r["key"] }
      expect(leaf_keys).to include("knowledge.agents")
      built_keys = result["built"].map { |b| b["key"] }
      expect(built_keys).not_to include("artifacts.catalogs.people")
    end
  end

  describe "#call(keys:)" do
    it "scopes to exactly the requested entry keys (derived)" do
      result = svc.call(keys: ["artifacts.catalogs.people"])
      built_keys = result["built"].map { |b| b["key"] }
      expect(built_keys).to eq(["artifacts.catalogs.people"])
      expect(result["published_leaves"]).to be_empty
    end

    it "scopes to exactly the requested entry keys (nested/tree)" do
      result = svc.call(keys: ["knowledge.agents"])
      leaf_keys = result["published_leaves"].map { |r| r["key"] }
      expect(leaf_keys).to all(eq("knowledge.agents"))
      expect(result["built"]).to be_empty
    end

    it "returns empty result when keys list is empty" do
      result = svc.call(keys: [])
      expect(result["built"]).to be_empty
      expect(result["published_leaves"]).to be_empty
    end
  end

  # Ported from spec/integration/write/build_spec.rb (deleted in ADR 0087)
  describe "publish_tree leaf detail" do
    let(:store) do
      FileUtils.mkdir_p(File.join(root, "zones/artifacts/agents"))
      s = store_from_manifest(root, zones: %w[artifacts], manifest: <<~YAML)
        version: textus/3
        zones:
          - { name: artifacts, kind: machine }
        entries:
          - key: artifacts.agents
            kind: nested
            path: artifacts/agents
            zone: artifacts
            owner: human:self
            publish:
              tree: "agents"
      YAML
      File.write(File.join(root, "zones/artifacts/agents/alice.md"),
                 "---\nname: alice\n---\nbody\n")
      File.write(File.join(root, "zones/artifacts/agents/bob.md"),
                 "---\nname: bob\n---\nbody\n")
      s
    end

    it "mirrors every file in the subtree into published_leaves, keyed by the entry" do
      events = []
      store.events.register(:file_published, :cap) { |key:, target:, **| events << [key, target] }

      result = svc.call

      expect(result["published_leaves"].length).to eq(2)
      expect(result["published_leaves"].map { |r| r["key"] }).to all(eq("artifacts.agents"))
      expect(result["published_leaves"].map { |r| File.basename(r["target"]) })
        .to contain_exactly("alice.md", "bob.md")
      expect(events.length).to eq(2)
    end
  end

  describe "External entry" do
    let(:store) do
      FileUtils.mkdir_p(File.join(root, "zones/knowledge/people"))
      FileUtils.mkdir_p(File.join(root, "zones/artifacts/catalogs"))
      s = store_from_manifest(root, zones: %w[knowledge artifacts], manifest: <<~YAML)
        version: textus/3
        zones:
          - { name: knowledge, kind: canon }
          - { name: artifacts, kind: machine }
        entries:
          - { key: knowledge.people, path: knowledge/people, zone: knowledge, owner: human:self, kind: nested }
          - key: artifacts.catalogs.big
            kind: derived
            path: artifacts/catalogs/big.md
            zone: artifacts
            owner: automation:auto
            compute: { kind: external, sources: [knowledge.people], command: "rake build:big" }
      YAML
      File.write(File.join(root, "zones/knowledge/people/alice.md"), "---\nname: alice\n---\n")
      File.write(File.join(root, "zones/artifacts/catalogs/big.md"),
                 "---\n_meta:\n  generated:\n    at: 2030-01-01T00:00:00Z\n---\nRUNNER OUTPUT\n")
      s
    end

    it "does not materialize the External entry (leaves the runner artifact untouched)" do
      store # trigger lazy fixture setup so the runner's artifact exists on disk
      before = File.read(File.join(root, "zones/artifacts/catalogs/big.md"))
      svc.call
      after = File.read(File.join(root, "zones/artifacts/catalogs/big.md"))
      expect(after).to eq(before)
      expect(after).to include("RUNNER OUTPUT")
    end

    it "omits the External entry from the built list" do
      result = svc.call
      built_keys = result["built"].map { |b| b["key"] }
      expect(built_keys).not_to include("artifacts.catalogs.big")
    end
  end

  describe "Intake entry with publish_to" do
    let(:store) do
      FileUtils.mkdir_p(File.join(root, "zones/artifacts"))
      s = store_from_manifest(root, zones: %w[artifacts], manifest: <<~YAML)
        version: textus/3
        zones:
          - { name: artifacts, kind: machine }
        entries:
          - key: artifacts.catalog
            kind: intake
            path: artifacts/catalog.txt
            zone: artifacts
            format: text
            owner: automation:auto
            publish:
              to: [CATALOG.txt, docs/catalog.txt]
            intake:
              handler: catalog_handler
      YAML
      File.write(File.join(root, "zones/artifacts/catalog.txt"), "one\ntwo\nthree\n")
      s
    end

    it "fans out the intake body to each publish_to target" do
      events = []
      store.events.register(:file_published, :cap) { |key:, target:, **| events << [key, target] }

      result = svc.call

      catalog = result["built"].find { |r| r["key"] == "artifacts.catalog" }
      expect(catalog).not_to be_nil
      expect(catalog["published_to"]).to eq(["CATALOG.txt", "docs/catalog.txt"])

      repo_root = File.dirname(root)
      expect(File.read(File.join(repo_root, "CATALOG.txt"))).to eq("one\ntwo\nthree\n")
      expect(File.read(File.join(repo_root, "docs/catalog.txt"))).to eq("one\ntwo\nthree\n")
      expect(events.map(&:first)).to contain_exactly("artifacts.catalog", "artifacts.catalog")
    end
  end

  describe "events" do
    it "fires :build_completed for derived entries and :file_published for all copies" do
      build_completed = []
      file_published  = []
      store.events.register(:build_completed, :cap1) { |key:, **| build_completed << key }
      store.events.register(:file_published,  :cap2) { |key:, **| file_published  << key }

      svc.call

      expect(build_completed).to include("artifacts.catalogs.people")
      expect(file_published).to include("artifacts.catalogs.people")
      expect(file_published).to include("knowledge.agents")
    end
  end
end
