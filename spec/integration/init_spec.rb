require "spec_helper"

RSpec.describe Textus::Init do
  it "scaffolds a .textus/ with the default manifest" do
    tmp = Dir.mktmpdir
    root = File.join(tmp, ".textus")
    Textus::Init.run(root)
    expect(File.exist?(File.join(root, "manifest.yaml"))).to be true
    expect(File.directory?(File.join(root, "schemas"))).to be true
    expect(File.read(File.join(root, "manifest.yaml"))).to include("version: textus/3")
  ensure
    FileUtils.remove_entry(tmp) if tmp && File.directory?(tmp)
  end

  it "declares a roles: block with capabilities and zone kinds" do
    tmp = Dir.mktmpdir
    root = File.join(tmp, ".textus")
    Textus::Init.run(root)
    contents = File.read(File.join(root, "manifest.yaml"))
    expect(contents).to include("can: [author, propose]").and include("kind: machine")
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

  it "creates .textus/steps/ with a README stub" do
    tmp = Dir.mktmpdir
    target = File.join(tmp, ".textus")
    Textus::Init.run(target)
    expect(File.directory?(File.join(target, "steps"))).to be true
    expect(File.read(File.join(target, "steps", "README.md"))).to include("discovered by convention")
  ensure
    FileUtils.remove_entry(tmp) if tmp && File.directory?(tmp)
  end

  it "scaffolds steps/README.md without dangling 'extension' terminology" do
    Dir.mktmpdir do |dir|
      target = File.join(dir, ".textus")
      Textus::Init.run(target)
      readme = File.read(File.join(target, "steps/README.md"))
      expect(readme).to include("Steps are discovered by convention")
      expect(readme).not_to match(/extensions register/i)
    end
  end

  it "declares all four zones and pre-creates their directories" do
    tmp = Dir.mktmpdir
    target = File.join(tmp, ".textus")
    Textus::Init.run(target)
    manifest = File.read(File.join(target, "manifest.yaml"))
    %w[knowledge notebook proposals artifacts].each do |z|
      expect(manifest).to include("name: #{z}"), "manifest should declare zone #{z}"
      expect(File.directory?(File.join(target, "zones", z))).to be(true), "zones/#{z}/ should exist"
      expect(File.exist?(File.join(target, "zones", z, ".gitkeep"))).to be true
    end
  ensure
    FileUtils.remove_entry(tmp) if tmp && File.directory?(tmp)
  end

  it "emits a .gitignore that ignores the .run runtime subtree" do
    Dir.mktmpdir do |dir|
      target = File.join(dir, ".textus")
      Textus::Init.run(target)

      gitignore = File.join(target, ".gitignore")
      expect(File.exist?(gitignore)).to be(true)
      expect(File.read(gitignore)).to include(".run/")
      expect(File.directory?(File.join(target, ".run"))).to be(true)
    end
  end

  it "does not scaffold legacy inbox/ directory or zone" do
    Dir.mktmpdir do |root|
      target = File.join(root, ".textus")
      Textus::Init.run(target)
      expect(File.directory?(File.join(target, "zones", "inbox"))).to be false
      expect(File.read(File.join(target, "manifest.yaml"))).not_to include("inbox")
    end
  end
end
