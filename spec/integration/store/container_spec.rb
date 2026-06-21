require "spec_helper"

RSpec.describe Textus::Store::Container do
  def build_container(root)
    manifest = Textus::Manifest.parse("version: textus/4\nlanes:\n  - { name: test, kind: canon }\nentries: []\n", root: root)
    file_store = Textus::Port::Storage::FileStore.new
    schemas = Textus::Schemas.new(File.join(root, "schemas"))
    audit_log = Textus::Port::AuditLog.new(root, max_size: 100, keep: 3)
    workflows = Textus::Workflow::Registry.new
    job_store = Textus::Port::Store.new(root: root).setup!
    described_class.new(
      manifest: manifest, file_store: file_store, schemas: schemas, root: root,
      audit_log: audit_log, workflows: workflows, job_store: job_store,
      gate: nil, compositor: nil, geometry: nil,
    )
  end

  it "bundles all required collaborators" do
    Dir.mktmpdir do |tmp|
      container = build_container(File.join(tmp, ".textus"))
      expect(container.manifest).to be_a(Textus::Manifest)
      expect(container.file_store).to be_a(Textus::Port::Storage::FileStore)
      expect(container.schemas).to be_a(Textus::Schemas)
      expect(container.root).to match(/\.textus\z/)
      expect(container.audit_log).to be_a(Textus::Port::AuditLog)
      expect(container.workflows).to be_a(Textus::Workflow::Registry)
      expect(container.job_store).to be_a(Textus::Port::Store)
    end
  end

  it "defaults optional attributes to nil and freezes" do
    Dir.mktmpdir do |tmp|
      container = build_container(File.join(tmp, ".textus"))
      expect(container.gate).to be_nil
      expect(container.compositor).to be_nil
      expect(container.geometry).to be_nil
      expect(container).to be_frozen
    end
  end

  it "is built once per Store and backs the Store's delegated readers", :aggregate_failures do
    Dir.mktmpdir do |tmp|
      Textus::Surface::CLI.run(
        ["--root=#{tmp}/.textus", "init"],
        stdin: StringIO.new(""), stdout: StringIO.new, stderr: StringIO.new, cwd: tmp,
      )
      store = Textus::Store.new(File.join(tmp, ".textus"))
      container = store.container

      expect(container).to be_a(Textus::Store::Container)
      expect(store.container).to be(container) # one Container per Store
      expect(store.manifest).to be(container.manifest)
      expect(store.file_store).to be(container.file_store)
      expect(store.schemas).to be(container.schemas)
      expect(store.root).to eq(container.root)
      expect(store.audit_log).to be(container.audit_log)
      expect(store.workflows).to be(container.workflows)
      expect(store.job_store).to be(container.job_store)
    end
  end
end
