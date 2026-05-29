# rubocop:disable Style/GlobalVars
require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Textus::Store do
  let(:tmp)  { Dir.mktmpdir("textus-store-spec") }
  let(:root) { File.join(tmp, ".textus") }

  before do
    FileUtils.mkdir_p(File.join(root, "schemas"))
    FileUtils.mkdir_p(File.join(root, "hooks"))
    FileUtils.mkdir_p(File.join(root, "zones/working"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, write_policy: [human] }
      entries:
        - { key: working.demo, path: working/demo, zone: working, schema: null, owner: human:patrick, kind: leaf}

    YAML
  end

  after { FileUtils.remove_entry(tmp) }

  describe "composition root" do
    it "exposes documented accessors" do
      store = described_class.new(root)
      expect(store.root).to eq(File.expand_path(root))
      expect(store.manifest).to be_a(Textus::Manifest)
      expect(store.schemas).to be_a(Textus::Schemas)
      expect(store.file_store).to be_a(Textus::Ports::Storage::FileStore)
      expect(store.audit_log).to be_a(Textus::Ports::AuditLog)
      expect(store.events).to be_a(Textus::Hooks::EventBus)
      expect(store.rpc).to be_a(Textus::Hooks::RpcRegistry)
    end

    it "no longer responds to reader/writer/schema_for" do
      store = described_class.new(root)
      expect(store).not_to respond_to(:reader)
      expect(store).not_to respond_to(:writer)
      expect(store).not_to respond_to(:schema_for)
      expect { store.reader }.to raise_error(NoMethodError)
      expect { store.writer }.to raise_error(NoMethodError)
      expect { store.schema_for(:any) }.to raise_error(NoMethodError)
    end

    it "no longer exposes load_hooks (inlined into initialize in 0.18.0)" do
      expect(described_class.instance_methods).not_to include(:load_hooks)
    end
  end

  describe ".discover" do
    it "walks up from start_dir to find .textus" do
      nested = File.join(tmp, "a", "b", "c")
      FileUtils.mkdir_p(nested)
      store = described_class.discover(nested)
      expect(store.root).to eq(File.expand_path(root))
    end

    it "honors an explicit root: argument" do
      store = described_class.discover(Dir.pwd, root: root)
      expect(store.root).to eq(File.expand_path(root))
    end

    it "raises IoError when no .textus directory is found" do
      bare = Dir.mktmpdir("no-textus")
      expect { described_class.discover(bare) }.to raise_error(Textus::IoError)
      FileUtils.remove_entry(bare)
    end
  end

  describe "hook bootstrapping" do
    it "loads hook files from <root>/hooks at construction time" do
      File.write(File.join(root, "hooks/marker.rb"), <<~RUBY)
        $textus_store_spec_seen = []
        Textus.hook do |reg|
          reg.on(:store_loaded, :marker) { |**| $textus_store_spec_seen << :loaded }
        end
      RUBY
      $textus_store_spec_seen = nil
      described_class.new(root)
      expect($textus_store_spec_seen).to eq([:loaded])
    ensure
      $textus_store_spec_seen = nil
    end
  end
end
# rubocop:enable Style/GlobalVars
