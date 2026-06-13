require "spec_helper"

RSpec.describe "Key grammar enforcement" do
  include_context "textus_store_fixture"

  before do
    FileUtils.mkdir_p(File.join(root, "data/working"))
  end

  def write_manifest(entries_yaml)
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      lanes:
        - { name: working, kind: canon }
      entries:
      #{entries_yaml}
    YAML
  end

  describe "manifest load — declared keys" do
    it "rejects an underscore in a declared key" do
      write_manifest("  - { key: working.bad_key, path: working/bad_key.md, lane: working, kind: leaf }")
      expect { Textus::Manifest.load(root) }.to raise_error(Textus::UsageError, /invalid key segment 'bad_key'/)
    end

    it "rejects uppercase in a declared key" do
      write_manifest("  - { key: working.Foo, path: working/Foo.md, lane: working, kind: leaf }")
      expect { Textus::Manifest.load(root) }.to raise_error(Textus::UsageError, /invalid key segment 'Foo'/)
    end

    it "rejects a slash inside a segment (slashes split into a key with empty segments)" do
      write_manifest("  - { key: 'working./bad', path: working/bad.md, lane: working, kind: leaf }")
      expect { Textus::Manifest.load(root) }.to raise_error(Textus::UsageError)
    end

    it "rejects more than 8 segments" do
      key = (1..9).map { |i| "s#{i}" }.join(".")
      write_manifest("  - { key: #{key}, path: working/x.md, lane: working, kind: leaf }")
      # zone won't match working but key validation runs first via initialize
      expect { Textus::Manifest.load(root) }.to raise_error(Textus::UsageError, /max 8/)
    end

    it "rejects a segment longer than 64 chars" do
      long = "a" * 65
      write_manifest("  - { key: working.#{long}, path: working/x.md, lane: working, kind: leaf }")
      expect { Textus::Manifest.load(root) }.to raise_error(Textus::UsageError, /exceeds 64 chars/)
    end

    it "accepts internal hyphens and digits" do
      write_manifest("  - { key: working.foo-bar-2, path: working/foo-bar-2.md, lane: working, kind: leaf }")
      expect { Textus::Manifest.load(root) }.not_to raise_error
    end
  end

  describe "Store#put — runtime validation" do
    before do
      write_manifest("  - { key: working.foo, path: working/foo.md, lane: working, nested: false, kind: leaf }")
    end

    it "rejects illegal key at put time before any write" do
      store = Textus::Store.new(root)
      expect do
        store.as("human").put("working.Bad_Name", meta: { "name" => "Bad_Name" }, body: "x")
      end.to raise_error(Textus::UsageError, /invalid key segment/)
    end
  end

  describe "UnknownKey suggestions" do
    it "attaches ranked suggestions when a near-miss key is requested" do
      write_manifest(<<~YAML)
        - { key: working.notes, path: working/notes, lane: working, kind: nested }
      YAML
      FileUtils.mkdir_p(File.join(root, "data/working/notes"))
      %w[alpha beta gamma].each do |n|
        File.write(File.join(root, "data/working/notes/#{n}.md"), "---\nname: #{n}\n---\nx\n")
      end
      store = Textus::Store.new(root)
      begin
        store.as(Textus::Role::DEFAULT).get("workng.notes.alpha")
        raise "expected UnknownKey"
      rescue Textus::UnknownKey => e
        expect(e.suggestions).to include("working.notes.alpha")
        expect(e.suggestions.length).to be <= 5
        expect(e.message).to match(/did you mean/)
        expect(e.to_envelope["details"]["suggestions"]).to include("working.notes.alpha")
      end
    end
  end

  describe "Manifest#enumerate — illegal filenames" do
    it "warns and skips illegal nested filenames rather than raising" do
      write_manifest(<<~YAML)
        - { key: working.notes, path: working/notes, lane: working, kind: nested }
      YAML
      FileUtils.mkdir_p(File.join(root, "data/working/notes"))
      File.write(File.join(root, "data/working/notes/Bad_Name.md"), "---\n---\nx")
      File.write(File.join(root, "data/working/notes/good-name.md"), "---\n---\nx")

      manifest = Textus::Manifest.load(root)
      rows = nil
      expect { rows = manifest.resolver.enumerate }.to output(/illegal key segment 'Bad_Name'/).to_stderr
      keys = rows.map { |r| r[:key] }
      expect(keys).to include("working.notes.good-name")
      expect(keys).not_to include("working.notes.Bad_Name")
    end
  end
end
