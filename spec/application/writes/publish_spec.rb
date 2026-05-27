require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Textus::Application::Writes::Publish do
  include_context "textus_store_fixture"

  let(:store) { Textus::Store.new(root) }

  def write_manifest(yaml)
    File.write(File.join(root, "manifest.yaml"), yaml)
  end

  context "with two nested leaves under publish_each" do
    before do
      FileUtils.mkdir_p(File.join(root, "zones/working/agents"))
      write_manifest(<<~YAML)
        version: textus/3
        zones:
          - { name: working, write_policy: [human, agent, runner, builder] }
        entries:
          - key: working.agents
            kind: nested
            path: working/agents
            zone: working
            schema: null
            owner: human:self
            nested: true
            publish_each: "agents/{basename}.md"
      YAML
      File.write(File.join(root, "zones/working/agents/alice.md"),
                 "---\nname: alice\n---\nbody\n")
      File.write(File.join(root, "zones/working/agents/bob.md"),
                 "---\nname: bob\n---\nbody\n")
    end

    it "publishes each nested leaf to its publish_each target" do
      events = []
      store.bus.register(:file_published, :cap) { |key:, target:, **| events << [key, target] }

      ctx = test_ctx(role: "builder")
      res = build_publish(store, ctx).call

      expect(res["protocol"]).to eq(Textus::PROTOCOL)
      expect(res["published_leaves"].length).to eq(2)
      keys = res["published_leaves"].map { |r| r["key"] }
      expect(keys).to contain_exactly("working.agents.alice", "working.agents.bob")
      expect(events.length).to eq(2)
    end

    it "filters by prefix" do
      ctx = test_ctx(role: "builder")
      res = build_publish(store, ctx).call(prefix: "working.agents.alice")
      expect(res["published_leaves"].map { |r| r["key"] }).to eq(["working.agents.alice"])
    end
  end

  context "with a Derived entry with publish_to and a Nested entry with publish_each" do
    before do
      FileUtils.mkdir_p(File.join(root, "zones/working/people"))
      FileUtils.mkdir_p(File.join(root, "zones/output"))
      FileUtils.mkdir_p(File.join(root, "templates"))

      write_manifest(<<~YAML)
        version: textus/3
        zones:
          - { name: working, write_policy: [human, agent, runner] }
          - { name: output, write_policy: [builder] }
        entries:
          - { key: working.people, path: working/people, zone: working, schema: null, owner: o, nested: true, kind: nested }

          - key: output.catalogs.people
            kind: derived
            path: output/catalogs/people.md
            zone: output
            schema: null
            owner: builder:auto
            compute: { kind: projection, select: working.people, pluck: [name, org], sort_by: name }
            template: people.mustache
            publish_to: [PEOPLE.md]

          - key: working.agents
            kind: nested
            path: working/agents
            zone: working
            schema: null
            owner: human:self
            nested: true
            publish_each: "agents/{basename}.md"
      YAML

      File.write(File.join(root, "zones/working/people/alice.md"), "---\nname: alice\norg: x\n---\n")
      File.write(File.join(root, "zones/working/people/bob.md"),   "---\nname: bob\norg: y\n---\n")
      File.write(File.join(root, "templates/people.mustache"),
                 "{{#entries}}- {{name}} ({{org}})\n{{/entries}}")
      FileUtils.mkdir_p(File.join(root, "zones/working/agents"))
      File.write(File.join(root, "zones/working/agents/claude.md"), "---\nname: claude\n---\nbody\n")
    end

    it "returns the combined {protocol, built, published_leaves} shape" do
      ctx = test_ctx(role: "builder")
      res = build_publish(store, ctx).call

      expect(res["protocol"]).to eq(Textus::PROTOCOL)
      expect(res).to have_key("built")
      expect(res).to have_key("published_leaves")

      built_keys = res["built"].map { |b| b["key"] }
      expect(built_keys).to include("output.catalogs.people")

      leaf_keys = res["published_leaves"].map { |r| r["key"] }
      expect(leaf_keys).to include("working.agents.claude")
    end

    it "materializes the Derived entry and writes it to the publish_to target" do
      ctx = test_ctx(role: "builder")
      build_publish(store, ctx).call

      repo_root = File.dirname(root)
      published_path = File.join(repo_root, "PEOPLE.md")
      expect(File.exist?(published_path)).to be true
      content = File.read(published_path)
      expect(content).to include("alice")
    end

    it "fires :build_completed for derived entries and :file_published for all copies" do
      build_completed = []
      file_published  = []
      store.bus.register(:build_completed, :cap1) { |key:, **| build_completed << key }
      store.bus.register(:file_published,  :cap2) { |key:, **| file_published  << key }

      ctx = test_ctx(role: "builder")
      build_publish(store, ctx).call

      expect(build_completed).to include("output.catalogs.people")
      expect(file_published).to include("output.catalogs.people")
      expect(file_published).to include("working.agents.claude")
    end
  end

  context "with an Intake entry that has publish_to" do
    before do
      FileUtils.mkdir_p(File.join(root, "zones/output"))
      write_manifest(<<~YAML)
        version: textus/3
        zones:
          - { name: output, write_policy: [runner, builder] }
        entries:
          - key: output.catalog
            kind: intake
            path: output/catalog.txt
            zone: output
            format: text
            owner: builder:auto
            publish_to: [CATALOG.txt, docs/catalog.txt]
            intake:
              handler: catalog_handler
      YAML
      # Seed a refreshed body directly — Publish reads it, doesn't generate it.
      File.write(File.join(root, "zones/output/catalog.txt"), "one\ntwo\nthree\n")
    end

    it "fans out the intake body to each publish_to target" do
      events = []
      store.bus.register(:file_published, :cap) { |key:, target:, **| events << [key, target] }

      ctx = test_ctx(role: "builder")
      res = build_publish(store, ctx).call

      built = res["built"]
      catalog = built.find { |r| r["key"] == "output.catalog" }
      expect(catalog).not_to be_nil
      expect(catalog["published_to"]).to eq(["CATALOG.txt", "docs/catalog.txt"])

      repo_root = File.dirname(root)
      expect(File.read(File.join(repo_root, "CATALOG.txt"))).to eq("one\ntwo\nthree\n")
      expect(File.read(File.join(repo_root, "docs/catalog.txt"))).to eq("one\ntwo\nthree\n")
      expect(events.map(&:first)).to contain_exactly("output.catalog", "output.catalog")
    end

    it "skips intake entries with no publish_to" do
      # Overwrite the manifest without publish_to; same body file.
      write_manifest(<<~YAML)
        version: textus/3
        zones:
          - { name: output, write_policy: [runner, builder] }
        entries:
          - key: output.catalog
            kind: intake
            path: output/catalog.txt
            zone: output
            format: text
            owner: builder:auto
            intake:
              handler: catalog_handler
      YAML
      store_no_publish = Textus::Store.new(root)
      ctx = test_ctx(role: "builder")
      res = build_publish(store_no_publish, ctx).call
      expect(res["built"]).to be_empty
    end
  end

  context "with a publish_each target that escapes the repo root" do
    before do
      FileUtils.mkdir_p(File.join(root, "zones/working/bad"))
      write_manifest(<<~YAML)
        version: textus/3
        zones:
          - { name: working, write_policy: [human, agent, runner, builder] }
        entries:
          - key: working.bad
            kind: nested
            path: working/bad
            zone: working
            schema: null
            owner: human:self
            nested: true
            publish_each: "../../../etc/{basename}.md"
      YAML
      File.write(File.join(root, "zones/working/bad/x.md"),
                 "---\nname: x\n---\nbody\n")
    end

    it "rejects publish_each targets that escape repo root" do
      ctx = test_ctx(role: "builder")
      expect do
        build_publish(store, ctx).call
      end.to raise_error(Textus::PublishError, /escapes repo root/)
    end
  end
end
