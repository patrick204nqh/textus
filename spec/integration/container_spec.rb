require "spec_helper"

RSpec.describe Textus::Container do
  it "is a Data class bundling collaborators" do
    container = described_class.new(
      manifest: :m, file_store: :fs, schemas: :s, root: "/r",
      audit_log: :a, events: :e, rpc: :rpc
    )
    expect(container.manifest).to eq(:m)
    expect(container.file_store).to eq(:fs)
    expect(container.schemas).to eq(:s)
    expect(container.root).to eq("/r")
    expect(container.audit_log).to eq(:a)
    expect(container.events).to eq(:e)
    expect(container.rpc).to eq(:rpc)
    expect(container).to be_frozen
  end

  it "is built once per Store and backs the Store's delegated readers" do
    Dir.mktmpdir do |tmp|
      Textus::CLI.run(
        ["--root=#{tmp}/.textus", "init"],
        stdin: StringIO.new(""), stdout: StringIO.new, stderr: StringIO.new, cwd: tmp,
      )
      store = Textus::Store.new(File.join(tmp, ".textus"))
      container = store.container

      expect(container).to be_a(Textus::Container)
      expect(store.container).to be(container) # one Container per Store
      expect(store.manifest).to be(container.manifest)
      expect(store.file_store).to be(container.file_store)
      expect(store.schemas).to be(container.schemas)
      expect(store.root).to eq(container.root)
      expect(store.audit_log).to be(container.audit_log)
      expect(store.events).to be(container.events)
      expect(store.rpc).to be(container.rpc)
    end
  end
end
