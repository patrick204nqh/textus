require "spec_helper"
require "tmpdir"

RSpec.describe Textus::Operations do
  it "constructs from a store and exposes writes/reads/refresh namespaces" do
    Dir.mktmpdir do |tmp|
      Textus::CLI.run(["--root=#{tmp}/.textus", "init"], stdin: StringIO.new(""), stdout: StringIO.new, stderr: StringIO.new, cwd: tmp)
      store = Textus::Store.new(File.join(tmp, ".textus"))
      ops = Textus::Operations.for(store, role: "human")

      expect(ops.writes).to be_a(Textus::Operations::Writes)
      expect(ops.reads).to be_a(Textus::Operations::Reads)
      expect(ops.refresh).to be_a(Textus::Operations::Refresh)

      expect(ops.writes.put).to be_a(Textus::Application::Writes::Put)
      expect(ops.reads.get).to be_a(Textus::Application::Reads::Get)
      expect(ops.refresh.worker).to be_a(Textus::Application::Refresh::Worker)
    end
  end

  it "memoizes the writes/reads/refresh namespace objects" do
    Dir.mktmpdir do |tmp|
      Textus::CLI.run(["--root=#{tmp}/.textus", "init"], stdin: StringIO.new(""), stdout: StringIO.new, stderr: StringIO.new, cwd: tmp)
      store = Textus::Store.new(File.join(tmp, ".textus"))
      ops = Textus::Operations.for(store, role: "human")

      expect(ops.writes).to equal(ops.writes)
      expect(ops.reads).to equal(ops.reads)
    end
  end

  it "with_role returns a new Operations with a different role" do
    Dir.mktmpdir do |tmp|
      Textus::CLI.run(["--root=#{tmp}/.textus", "init"], stdin: StringIO.new(""), stdout: StringIO.new, stderr: StringIO.new, cwd: tmp)
      store = Textus::Store.new(File.join(tmp, ".textus"))
      ops = Textus::Operations.for(store, role: "human")
      other = ops.with_role("agent")

      expect(other.ctx.role).to eq("agent")
      expect(ops.ctx.role).to eq("human")
    end
  end
end
