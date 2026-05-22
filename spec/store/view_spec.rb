require "spec_helper"
require "fileutils"
require "tmpdir"

# Store::View is deprecated as of 0.9.1; it now returns a Textus::Application::Context.
# These specs are kept as a compatibility smoke-test until 0.10.0 removes View entirely.
RSpec.describe Textus::Store::View do
  let(:tmp)  { Dir.mktmpdir }
  let(:root) { File.join(tmp, ".textus") }

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

  it "returns a Textus::Application::Context instance" do
    store = Textus::Store.new(root)
    view = described_class.new(store)
    expect(view).to be_a(Textus::Application::Context)
  end

  it "exposes read methods (get, list, where)" do
    store = Textus::Store.new(root)
    view = described_class.new(store, as: "human")
    expect(view.get("working.x")["body"]).to eq("hi\n")
    expect(view.list).to be_an(Array)
    expect(view.where("working.x")["path"]).to end_with("working/x.md")
  end

  it "raises if writable: true with no as: role" do
    store = Textus::Store.new(root)
    expect { described_class.new(store, writable: true) }
      .to raise_error(Textus::UsageError, /writable Store::View requires/)
  end

  it "raises if writable: true with empty-string as: role" do
    store = Textus::Store.new(root)
    expect { described_class.new(store, writable: true, as: "") }
      .to raise_error(Textus::UsageError, /writable Store::View requires/)
  end

  it "permits writes when constructed with an as: role that has permission" do
    store = Textus::Store.new(root)
    v = described_class.new(store, writable: true, as: "script")
    env = v.put("intake.demo", meta: { "name" => "demo" }, body: "hello")
    expect(env["key"]).to eq("intake.demo")
  end

  it "allows a per-call as: override of the bound role" do
    store = Textus::Store.new(root)
    v = described_class.new(store, writable: true, as: "script")
    env = v.put("working.x", meta: { "name" => "x" }, body: "updated", as: "human")
    expect(env["key"]).to eq("working.x")
  end
end
