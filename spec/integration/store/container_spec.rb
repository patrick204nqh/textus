require "spec_helper"

RSpec.describe Textus::Store::Container do
  def build_infra(root)
    Textus::Store::Container::Infrastructure.new(
      file_store: Textus::Port::Storage::FileStore.new,
      schemas: Textus::Schemas.new(File.join(root, "schemas")),
      audit_log: Textus::Port::AuditLog.new(root, max_size: 100, keep: 3),
      job_store: Textus::Port::Store.new(root: root).setup!,
      geometry: Textus::Store::Geometry.new(root),
    )
  end

  def build_coord(manifest)
    Textus::Store::Container::Coordination.new(
      manifest: manifest,
      workflows: Textus::Workflow::Registry.new,
      compositor: nil,
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
      expect(container.schemas).to be_a(Textus::Schemas)
      expect(container.root).to match(/\.textus\z/)
      expect(container.audit_log).to be_a(Textus::Port::AuditLog)
      expect(container.workflows).to be_a(Textus::Workflow::Registry)
      expect(container.job_store).to be_a(Textus::Port::Store)
    end
  end

  it "defaults optional attributes to nil" do
    Dir.mktmpdir do |tmp|
      container = build_container(File.join(tmp, ".textus"))
      expect(container.compositor).to be_nil
    end
  end

  it "backs the Store's delegated readers via Infra/Coord composition", :aggregate_failures do
    Dir.mktmpdir do |tmp|
      Textus::Surface::CLI.run(
        ["--root=#{tmp}/.textus", "init"],
        stdin: StringIO.new(""), stdout: StringIO.new, stderr: StringIO.new, cwd: tmp,
      )
      store = Textus::Store.new(File.join(tmp, ".textus"))
      container = store.container

      expect(container).to be_a(Textus::Store::Container)
      expect(container.infra).to be_a(Textus::Store::Container::Infrastructure)
      expect(container.coord).to be_a(Textus::Store::Container::Coordination)
      expect(container.manifest).to be_a(Textus::Manifest)
      expect(container.root).to be_a(String)
    end
  end

  it "dispatches through Bus" do
    Dir.mktmpdir do |tmp|
      dir = File.join(tmp, ".textus")
      Textus::Surface::CLI.run(
        ["--root=#{dir}", "init"],
        stdin: StringIO.new(""), stdout: StringIO.new, stderr: StringIO.new, cwd: tmp,
      )
      store = Textus::Store.new(dir)
      spec = Textus::VerbRegistry.for(:list)
      result = store.dispatch(spec:, inputs: { prefix: nil }, role: "admin")
      expect(result).to be_an(Array)
    end
  end
end
