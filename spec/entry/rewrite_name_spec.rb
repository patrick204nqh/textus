require "spec_helper"
require "tmpdir"

RSpec.describe "Entry strategy: rewrite_name" do
  describe "Markdown" do
    it "rewrites meta.name to match new basename" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "newname.md")
        File.write(path, "---\nname: oldname\n---\nbody\n")
        Textus::Entry::Markdown.rewrite_name(path, "newname")
        parsed = Textus::Entry::Markdown.parse(File.read(path), path: path)
        expect(parsed["_meta"]["name"]).to eq("newname")
        expect(parsed["body"]).to eq("body\n")
      end
    end

    it "no-ops when name already matches" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "newname.md")
        File.write(path, "---\nname: newname\n---\nbody\n")
        before = File.read(path)
        Textus::Entry::Markdown.rewrite_name(path, "newname")
        expect(File.read(path)).to eq(before)
      end
    end

    it "no-ops when meta has no name" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "newname.md")
        File.write(path, "---\nother: 1\n---\nbody\n")
        before = File.read(path)
        Textus::Entry::Markdown.rewrite_name(path, "newname")
        expect(File.read(path)).to eq(before)
      end
    end
  end

  describe "Text" do
    it "is a no-op (text has no meta)" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "foo.txt")
        File.write(path, "plain text")
        Textus::Entry::Text.rewrite_name(path, "bar")
        expect(File.read(path)).to eq("plain text")
      end
    end
  end
end
