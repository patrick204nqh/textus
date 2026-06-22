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
      gate: nil, compositor: nil, geometry: nil
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

  it "backs the Store's delegated readers via a LazyContainer", :aggregate_failures do
    Dir.mktmpdir do |tmp|
      Textus::Surface::CLI.run(
        ["--root=#{tmp}/.textus", "init"],
        stdin: StringIO.new(""), stdout: StringIO.new, stderr: StringIO.new, cwd: tmp,
      )
      store = Textus::Store.new(File.join(tmp, ".textus"))
      proxy = store.container

      expect(proxy).to be_a(Textus::LazyContainer)
      expect(store.container).to be(proxy)

      resolved = proxy.__send__(:resolve)
      expect(resolved).to be_a(Textus::Store::Container)
      expect(proxy.manifest).to be(resolved.manifest)
      expect(proxy.file_store).to be(resolved.file_store)
      expect(proxy.schemas).to be(resolved.schemas)
      expect(proxy.root).to eq(resolved.root)
      expect(proxy.audit_log).to be(resolved.audit_log)
      expect(proxy.workflows).to be(resolved.workflows)
      expect(proxy.job_store).to be(resolved.job_store)
    end
  end

  it "does not mutate Gate ivar after construction" do
    Dir.mktmpdir do |tmp|
      dir = File.join(tmp, ".textus")
      Textus::Surface::CLI.run(
        ["--root=#{dir}", "init"],
        stdin: StringIO.new(""), stdout: StringIO.new, stderr: StringIO.new, cwd: tmp,
      )
      store = Textus::Store.new(dir)
      gate = store.gate
      expect(gate.instance_variable_get(:@container)).to be_a(Textus::LazyContainer)
    end
  end
end
