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

  describe "unified dispatch" do
    let(:store) { described_class.new(root) }

    it "dispatches read/write/ops/rule verbs" do
      expect(store.list).to be_an(Array)
      expect(store.boot).to be_a(Hash)
      expect(store.rule_list).to be_an(Array)
    end

    it "rejects unknown verbs" do
      expect(store).not_to respond_to(:frobnicate)
      expect { store.list("knowledge") }.to raise_error(ArgumentError, /keyword arguments/)
    end
  end
end
