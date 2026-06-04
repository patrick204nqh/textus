require "spec_helper"

RSpec.describe Textus::Write::Build do
  include_context "textus_store_fixture"

  context "with a nested entry under publish_tree" do
    let(:store) do
      FileUtils.mkdir_p(File.join(root, "zones/artifacts/agents"))
      s = store_from_manifest(root, zones: %w[artifacts], manifest: <<~YAML)
        version: textus/3
        zones:
          - { name: artifacts, kind: derived }
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

      res = store.as("automation").build

      expect(res["protocol"]).to eq(Textus::PROTOCOL)
      expect(res["published_leaves"].length).to eq(2)
      # publish_tree is path-driven: each mirrored file is reported under the
      # entry key (no per-leaf enumeration).
      expect(res["published_leaves"].map { |r| r["key"] }).to all(eq("artifacts.agents"))
      expect(res["published_leaves"].map { |r| File.basename(r["target"]) })
        .to contain_exactly("alice.md", "bob.md")
      expect(events.length).to eq(2)
    end

    it "skips the entry when the prefix filter does not match it" do
      res = store.as("automation").build(prefix: "something.else")
      expect(res["published_leaves"]).to be_empty
    end

    it "includes the entry when the prefix filter matches it" do
      res = store.as("automation").build(prefix: "artifacts")
      expect(res["published_leaves"].map { |r| r["key"] }).to all(eq("artifacts.agents"))
      expect(res["published_leaves"].length).to eq(2)
    end
  end

  context "with a Derived entry with publish_to and a Nested entry with publish_tree" do
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
      FileUtils.mkdir_p(File.join(root, "zones/knowledge/agents"))
      File.write(File.join(root, "zones/knowledge/agents/claude.md"), "---\nname: claude\n---\nbody\n")
      s
    end

    it "includes a 'pruned' array in the build envelope" do
      res = store.as("automation").build
      expect(res).to have_key("pruned")
      expect(res["pruned"]).to be_an(Array)
    end

    it "returns the combined {protocol, built, published_leaves} shape" do
      res = store.as("automation").build

      expect(res["protocol"]).to eq(Textus::PROTOCOL)
      expect(res).to have_key("built")
      expect(res).to have_key("published_leaves")

      built_keys = res["built"].map { |b| b["key"] }
      expect(built_keys).to include("artifacts.catalogs.people")

      leaf_keys = res["published_leaves"].map { |r| r["key"] }
      expect(leaf_keys).to include("knowledge.agents")
    end

    it "materializes the Derived entry and writes it to the publish_to target" do
      store.as("automation").build

      repo_root = File.dirname(root)
      published_path = File.join(repo_root, "PEOPLE.md")
      expect(File.exist?(published_path)).to be true
      content = File.read(published_path)
      expect(content).to include("alice")
    end

    it "fires :build_completed for derived entries and :file_published for all copies" do
      build_completed = []
      file_published  = []
      store.events.register(:build_completed, :cap1) { |key:, **| build_completed << key }
      store.events.register(:file_published,  :cap2) { |key:, **| file_published  << key }

      store.as("automation").build

      expect(build_completed).to include("artifacts.catalogs.people")
      expect(file_published).to include("artifacts.catalogs.people")
      expect(file_published).to include("knowledge.agents")
    end
  end

  context "with an External (out-of-band) derived entry" do
    let(:store) do
      FileUtils.mkdir_p(File.join(root, "zones/knowledge/people"))
      FileUtils.mkdir_p(File.join(root, "zones/artifacts/catalogs"))
      s = store_from_manifest(root, zones: %w[knowledge artifacts], manifest: <<~YAML)
        version: textus/3
        zones:
          - { name: knowledge, kind: canon }
          - { name: artifacts, kind: derived }
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
      # The runner's artifact already exists on disk (textus does not generate it).
      File.write(File.join(root, "zones/artifacts/catalogs/big.md"),
                 "---\n_meta:\n  generated:\n    at: 2030-01-01T00:00:00Z\n---\nRUNNER OUTPUT\n")
      s
    end

    it "does not materialize the External entry (leaves the runner's artifact untouched)" do
      store # trigger lazy fixture setup so the runner's artifact exists on disk
      before = File.read(File.join(root, "zones/artifacts/catalogs/big.md"))
      store.as("automation").build
      after = File.read(File.join(root, "zones/artifacts/catalogs/big.md"))
      expect(after).to eq(before)
      expect(after).to include("RUNNER OUTPUT")
    end

    it "omits the External entry from the built list" do
      res = store.as("automation").build
      built_keys = res["built"].map { |b| b["key"] }
      expect(built_keys).not_to include("artifacts.catalogs.big")
    end
  end

  context "with an Intake entry that has publish_to" do
    let(:store) do
      FileUtils.mkdir_p(File.join(root, "zones/artifacts"))
      s = store_from_manifest(root, zones: %w[artifacts], manifest: <<~YAML)
        version: textus/3
        zones:
          - { name: artifacts, kind: derived }
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
      # Seed a fetched body directly — Publish reads it, doesn't generate it.
      File.write(File.join(root, "zones/artifacts/catalog.txt"), "one\ntwo\nthree\n")
      s
    end

    it "fans out the intake body to each publish_to target" do
      events = []
      store.events.register(:file_published, :cap) { |key:, target:, **| events << [key, target] }

      res = store.as("automation").build

      built = res["built"]
      catalog = built.find { |r| r["key"] == "artifacts.catalog" }
      expect(catalog).not_to be_nil
      expect(catalog["published_to"]).to eq(["CATALOG.txt", "docs/catalog.txt"])

      repo_root = File.dirname(root)
      expect(File.read(File.join(repo_root, "CATALOG.txt"))).to eq("one\ntwo\nthree\n")
      expect(File.read(File.join(repo_root, "docs/catalog.txt"))).to eq("one\ntwo\nthree\n")
      expect(events.map(&:first)).to contain_exactly("artifacts.catalog", "artifacts.catalog")
    end

    it "skips intake entries with no publish_to" do
      store # trigger lazy setup so root/.textus dir exists before overwriting manifest
      # Overwrite the manifest without publish_to; same body file.
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/3
        zones:
          - { name: artifacts, kind: derived }
        entries:
          - key: artifacts.catalog
            kind: intake
            path: artifacts/catalog.txt
            zone: artifacts
            format: text
            owner: automation:auto
            intake:
              handler: catalog_handler
      YAML
      store_no_publish = Textus::Store.new(root)
      res = store_no_publish.as("automation").build
      expect(res["built"]).to be_empty
    end
  end
end
