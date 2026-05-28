require "spec_helper"
require "tmpdir"

RSpec.describe Textus::Container do
  it "is a Data class bundling collaborators" do
    container = described_class.new(
      manifest: :m, file_store: :fs, schemas: :s, root: "/r",
      audit_log: :a, events: :e, rpc: :rpc, authorizer: :auth
    )
    expect(container.manifest).to eq(:m)
    expect(container.file_store).to eq(:fs)
    expect(container.schemas).to eq(:s)
    expect(container.root).to eq("/r")
    expect(container.audit_log).to eq(:a)
    expect(container.events).to eq(:e)
    expect(container.rpc).to eq(:rpc)
    expect(container.authorizer).to eq(:auth)
    expect(container).to be_frozen
  end

  it "exposes a build helper that constructs an Authorizer from the manifest" do
    Dir.mktmpdir do |tmp|
      Textus::CLI.run(
        ["--root=#{tmp}/.textus", "init"],
        stdin: StringIO.new(""), stdout: StringIO.new, stderr: StringIO.new, cwd: tmp,
      )
      store = Textus::Store.new(File.join(tmp, ".textus"))
      container = Textus::Container.from_store(store)

      expect(container).to be_a(Textus::Container)
      expect(container.authorizer).to be_a(Textus::Domain::Authorizer)
      expect(container.manifest).to be(store.manifest)
      expect(container.file_store).to be(store.file_store)
      expect(container.schemas).to be(store.schemas)
      expect(container.root).to eq(store.root)
      expect(container.audit_log).to be(store.audit_log)
      expect(container.events).to be(store.events)
      expect(container.rpc).to be(store.rpc)
    end
  end
end
