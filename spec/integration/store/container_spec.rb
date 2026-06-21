require "spec_helper"

RSpec.describe Textus::Store::Container do
  it "is a Data class bundling collaborators" do
    Dir.mktmpdir do |tmp|
      root = File.join(tmp, ".textus")
      manifest = Textus::Manifest.parse("version: textus/4\nlanes:\n  - { name: test, kind: canon }\nentries: []\n", root: root)
      file_store = Textus::Port::Storage::FileStore.new
      schemas = Textus::Schemas.new(File.join(root, "schemas"))
      audit_log = Textus::Port::AuditLog.new(root, max_size: 100, keep: 3)
      workflows = Textus::Workflow::Registry.new
      job_store = Textus::Port::Store.new(root: root).setup!
      container = described_class.new(
        manifest: manifest, file_store: file_store, schemas: schemas, root: root,
        audit_log: audit_log, workflows: workflows, job_store: job_store,
        gate: nil, compositor: nil
      )
      expect(container.manifest).to be(manifest)
      expect(container.file_store).to be(file_store)
      expect(container.schemas).to be(schemas)
      expect(container.root).to eq(root)
      expect(container.audit_log).to be(audit_log)
      expect(container.workflows).to be(workflows)
      expect(container.job_store).to be(job_store)
      expect(container.gate).to be_nil
      expect(container.compositor).to be_nil
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
