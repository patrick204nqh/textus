require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Textus::Init do
  it "scaffolds a .textus/ with the default manifest" do
    tmp = Dir.mktmpdir
    root = File.join(tmp, ".textus")
    Textus::Init.run(root)
    expect(File.exist?(File.join(root, "manifest.yaml"))).to be true
    expect(File.directory?(File.join(root, "schemas"))).to be true
    expect(File.read(File.join(root, "manifest.yaml"))).to include("version: textus/2")
  ensure
    FileUtils.remove_entry(tmp) if tmp && File.directory?(tmp)
  end

  it "raises if .textus/ already exists" do
    tmp = Dir.mktmpdir
    root = File.join(tmp, ".textus")
    Textus::Init.run(root)
    expect { Textus::Init.run(root) }.to raise_error(Textus::UsageError)
  ensure
    FileUtils.remove_entry(tmp) if tmp && File.directory?(tmp)
  end

  it "creates .textus/hooks/ with a README stub" do
    tmp = Dir.mktmpdir
    target = File.join(tmp, ".textus")
    Textus::Init.run(target)
    expect(File.directory?(File.join(target, "hooks"))).to be true
    expect(File.read(File.join(target, "hooks", "README.md"))).to include("Textus.hook")
  ensure
    FileUtils.remove_entry(tmp) if tmp && File.directory?(tmp)
  end

  it "scaffolds hooks/README.md without dangling 'extension' terminology" do
    Dir.mktmpdir do |dir|
      target = File.join(dir, ".textus")
      Textus::Init.run(target)
      readme = File.read(File.join(target, "hooks/README.md"))
      expect(readme).to include("All hooks register through one DSL")
      expect(readme).not_to match(/extensions register/i)
    end
  end

  it "declares all five zones and pre-creates their directories" do
    tmp = Dir.mktmpdir
    target = File.join(tmp, ".textus")
    Textus::Init.run(target)
    manifest = File.read(File.join(target, "manifest.yaml"))
    %w[canon working intake pending derived].each do |z|
      expect(manifest).to include("name: #{z}"), "manifest should declare zone #{z}"
      expect(File.directory?(File.join(target, "zones", z))).to be(true), "zones/#{z}/ should exist"
      expect(File.exist?(File.join(target, "zones", z, ".gitkeep"))).to be true
    end
  ensure
    FileUtils.remove_entry(tmp) if tmp && File.directory?(tmp)
  end
end
