# spec/init_with_agent_spec.rb
require "spec_helper"

RSpec.describe "Textus::Init with_agent profile" do
  def init(with_agent:)
    dir = Dir.mktmpdir
    root = File.join(dir, ".textus")
    result = Textus::Init.run(root, with_agent: with_agent)
    [dir, root, result]
  end

  it "leaves the default manifest byte-identical when with_agent is false" do
    dir, root, = init(with_agent: false)
    expect(File.read(File.join(root, "manifest.yaml"))).to eq(Textus::Init::DEFAULT_MANIFEST)
  ensure
    FileUtils.remove_entry(dir) if dir && File.directory?(dir)
  end
end
