require "spec_helper"

RSpec.describe Textus::Store::Container do
  def build_infra(root)
    geometry = Textus::Store::Layout.new(root)
    Textus::Store::Container::Infrastructure.new(
      file_store: Textus::Port::Storage::FileStore.new,
      schemas: Textus::Schema::Registry.new(File.join(root, "schemas")),
      audit_log: Textus::Port::AuditLog.new(layout: geometry, max_size: 100, keep: 3),
      job_store: Textus::Port::Store.new(root: root).setup!,
      layout: geometry,
    )
  end

  def build_coord(manifest)
    Textus::Store::Container::Coordination.new(
      manifest: manifest,
      workflows: Textus::Workflow::Registry.new,
      pipeline: nil,
    )
  end

  def build_container(root)
    manifest = Textus::Manifest.parse("version: textus/4\nlanes:\n  - { name: test, kind: canon }\nentries: []\n", root: root)
    infra = build_infra(root)
    coord = build_coord(manifest)
    Textus::Store::Container.new(infra, coord)
  end

  it "bundles all required collaborators" do
    Dir.mktmpdir do |tmp|
      container = build_container(File.join(tmp, ".textus"))
      expect(container.manifest).to be_a(Textus::Manifest)
      expect(container.file_store).to be_a(Textus::Port::Storage::FileStore)
      expect(container.schemas).to be_a(Textus::Schema::Registry)
      expect(container.root).to match(/\.textus\z/)
      expect(container.audit_log).to be_a(Textus::Port::AuditLog)
      expect(container.workflows).to be_a(Textus::Workflow::Registry)
      expect(container.job_store).to be_a(Textus::Port::Store)
    end
  end

  it "defaults pipeline to nil" do
    Dir.mktmpdir do |tmp|
      container = build_container(File.join(tmp, ".textus"))
      expect(container.pipeline).to be_nil
    end
  end

  it "backs the Store via ContainerProxy with expected accessors", :aggregate_failures do
    Dir.mktmpdir do |tmp|
      Textus::Surface::CLI.run(
        ["--root=#{tmp}/.textus", "init"],
        stdin: StringIO.new(""), stdout: StringIO.new, stderr: StringIO.new, cwd: tmp,
      )
      store = Textus::Store.new(File.join(tmp, ".textus"))
      container = store.container

      expect(container).to be_a(Textus::Store::ContainerProxy)
      expect(container.manifest).to be_a(Textus::Manifest)
      expect(container.root).to be_a(String)
      expect(container.pipeline).not_to be_nil
    end
  end

  it "dispatches through Store" do
    Dir.mktmpdir do |tmp|
      dir = File.join(tmp, ".textus")
      Textus::Surface::CLI.run(
        ["--root=#{dir}", "init"],
        stdin: StringIO.new(""), stdout: StringIO.new, stderr: StringIO.new, cwd: tmp,
      )
      store = Textus::Store.new(dir)
      result = store.entry(:list, prefix: nil)
      expect(result).to be_an(Array)
    end
  end
end
