require "spec_helper"

RSpec.describe Textus::Store do
  let(:tmp)  { Dir.mktmpdir("textus-store-spec") }
  let(:root) { File.join(tmp, ".textus") }

  before do
    FileUtils.mkdir_p(File.join(root, "schemas"))
    FileUtils.mkdir_p(File.join(root, "data/knowledge"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/4
      lanes:
        - { name: knowledge, kind: canon }
      entries:
        - { key: knowledge.demo, path: knowledge/demo, lane: knowledge, owner: human:patrick, kind: leaf}

    YAML
  end

  after { FileUtils.remove_entry(tmp) }

  describe "composition root" do
    it "exposes documented accessors" do
      store = described_class.new(root)
      expect(store.root).to eq(File.expand_path(root))
      expect(store.manifest).to be_a(Textus::Manifest)
      expect(store.schemas).to be_a(Textus::Schema::Registry)
      expect(store.file_store).to be_a(Textus::Port::Storage::FileStore)
      expect(store.audit_log).to be_a(Textus::Port::AuditLog)
      expect(store.container.workflows).to be_a(Textus::Workflow::Registry)
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

    it "raises IoError when no .textus directory is found" do
      bare = Dir.mktmpdir("no-textus")
      expect { described_class.discover(bare) }.to raise_error(Textus::IoError)
      FileUtils.remove_entry(bare)
    end
  end

  describe "#with_role" do
    it "returns a Store oriented at the latest cursor and the role's propose_lane" do
      store = described_class.new(root)
      s = store.with_role("agent")
      expect(s).to be_a(Textus::Store)
      expect(s.role).to eq("agent")
      expect(s.cursor).to eq(store.audit_log.latest_seq)
      expect(s.propose_lane).to eq(store.manifest.policy.propose_lane_for("agent"))
    end
  end

  it "exposes container.workflows as a Workflow::Registry" do
    expect(described_class.new(root).container.workflows).to be_a(Textus::Workflow::Registry)
  end

  describe "unified dispatch via method_missing" do
    let(:store) { described_class.new(root) }

    it "dispatches a read verb via method name" do
      result = store.list
      expect(result).to be_an(Array)
    end

    it "dispatches :boot" do
      result = store.boot
      expect(result).to be_a(Hash)
    end

    it "dispatches :rule_list" do
      result = store.rule_list
      expect(result).to be_an(Array)
    end

    it "responds_to any registered verb" do
      expect(store).to respond_to(:list)
      expect(store).to respond_to(:get)
      expect(store).to respond_to(:boot)
      expect(store).to respond_to(:rule_list)
    end

    it "does not respond_to an unknown verb" do
      expect(store).not_to respond_to(:frobnicate)
    end

    it "requires keyword arguments for verbs" do
      expect { store.list("knowledge") }.to raise_error(ArgumentError, /keyword arguments only/)
    end
  end
end
