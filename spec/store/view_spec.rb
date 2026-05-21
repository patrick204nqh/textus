require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Textus::Store::View do
  let(:tmp)  { Dir.mktmpdir }
  let(:root) { File.join(tmp, ".textus") }
  let(:view) { described_class.new(Textus::Store.new(root)) }

  before do
    FileUtils.mkdir_p(File.join(root, "zones/working"))
    FileUtils.mkdir_p(File.join(root, "zones/intake"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/2
      zones:
        - { name: working, writable_by: [human] }
        - { name: intake,  writable_by: [script] }
      entries:
        - { key: working.x,    path: working/x.md,    zone: working }
        - { key: intake.demo,  path: intake/demo.md,  zone: intake }
    YAML
    File.write(File.join(root, "zones/working/x.md"), "---\nname: x\n---\nhi\n")
  end

  after { FileUtils.remove_entry(tmp) }

  it "exposes read methods" do
    expect(view.get("working.x")["body"]).to eq("hi\n")
    expect(view.list).to be_an(Array)
    expect(view.where("working.x")["path"]).to end_with("working/x.md")
  end

  it "raises on write attempts" do
    expect { view.put("working.x", meta: {}, body: "") }.to raise_error(Textus::UsageError, /read-only/)
    expect { view.delete("working.x") }.to raise_error(Textus::UsageError, /read-only/)
    expect { view.accept("working.x") }.to raise_error(Textus::UsageError, /read-only/)
  end

  it "READ_METHODS is a subset of Store's public instance methods (drift guard)" do
    missing = described_class::READ_METHODS - Textus::Store.public_instance_methods(false)
    expect(missing).to be_empty, "READ_METHODS contains methods not on Store: #{missing.inspect}"
  end

  it "is read-only by default" do
    store = Textus::Store.new(root)
    v = described_class.new(store)
    expect { v.put("intake.demo", meta: {}, body: "") }
      .to raise_error(Textus::UsageError, /read-only/)
  end

  it "permits writes when constructed writable with an as: role" do
    store = Textus::Store.new(root)
    v = described_class.new(store, writable: true, as: "script")
    env = v.put("intake.demo", meta: { "name" => "demo" }, body: "hello")
    expect(env["key"]).to eq("intake.demo")
  end

  it "raises if writable: true with no as: role" do
    store = Textus::Store.new(root)
    expect { described_class.new(store, writable: true) }
      .to raise_error(Textus::UsageError, /writable Store::View requires/)
  end

  it "allows a per-call as: override of the bound role" do
    store = Textus::Store.new(root)
    v = described_class.new(store, writable: true, as: "script")
    env = v.put("working.x", meta: { "name" => "x" }, body: "updated", as: "human")
    expect(env["key"]).to eq("working.x")
  end

  it "raises if writable: true with empty-string as: role" do
    store = Textus::Store.new(root)
    expect { described_class.new(store, writable: true, as: "") }
      .to raise_error(Textus::UsageError, /writable Store::View requires/)
  end
end
