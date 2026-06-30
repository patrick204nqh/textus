require "spec_helper"

RSpec.describe Textus::Store do
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
