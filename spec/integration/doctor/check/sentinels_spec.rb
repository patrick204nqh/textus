require "spec_helper"
require "digest"

RSpec.describe Textus::Doctor::Check::Sentinels do
  include_context "textus_store_fixture"

  let(:sentinels_dir) { File.join(root, ".state", "tracking", "sentinels") }

  before do
    FileUtils.mkdir_p(File.join(root, "data/knowledge"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/4
      lanes:
        - { name: knowledge, kind: canon }
      entries: []
    YAML
    FileUtils.mkdir_p(sentinels_dir)
  end

  it "returns empty array when no sentinels directory exists" do
    FileUtils.rm_rf(sentinels_dir)
    store = Textus::Store.new(root)
    expect(described_class.new(store.container).call).to eq([])
  end

  it "emits sentinel.parse_error for malformed JSON" do
    File.write(File.join(sentinels_dir, "bad.md.textus-managed.json"), "{not json")
    store = Textus::Store.new(root)
    issues = described_class.new(store.container).call
    expect(issues).to include(hash_including("code" => "sentinel.parse_error", "level" => "warning"))
  end

  it "emits sentinel.orphan when the target is missing" do
    File.write(File.join(sentinels_dir, "missing.md.textus-managed.json"), JSON.generate(
                                                                             "source" => ".textus/data/output/out.md",
                                                                             "target" => "missing.md",
                                                                             "sha256" => "deadbeef",
                                                                             "mode" => "copy",
                                                                           ))
    store = Textus::Store.new(root)
    issues = described_class.new(store.container).call
    expect(issues).to include(hash_including("code" => "sentinel.orphan", "level" => "warning"))
  end

  it "emits sentinel.drift when target bytes diverge from recorded sha256" do
    repo_root = File.dirname(root)
    target = File.join(repo_root, "drifted.md")
    File.binwrite(target, "original\n")
    sha = Digest::SHA256.hexdigest("original\n")
    File.write(File.join(sentinels_dir, "drifted.md.textus-managed.json"), JSON.generate(
                                                                             "source" => ".textus/data/output/out.md",
                                                                             "target" => "drifted.md",
                                                                             "sha256" => sha,
                                                                             "mode" => "copy",
                                                                           ))
    File.binwrite(target, "tampered\n")
    store = Textus::Store.new(root)
    issues = described_class.new(store.container).call
    expect(issues).to include(hash_including("code" => "sentinel.drift", "level" => "warning"))
  end

  it "returns no issues when sentinels are healthy" do
    repo_root = File.dirname(root)
    target = File.join(repo_root, "ok.md")
    File.binwrite(target, "ok\n")
    File.write(File.join(sentinels_dir, "ok.md.textus-managed.json"), JSON.generate(
                                                                        "source" => ".textus/data/output/out.md",
                                                                        "target" => "ok.md",
                                                                        "sha256" => Digest::SHA256.hexdigest("ok\n"),
                                                                        "mode" => "copy",
                                                                      ))
    store = Textus::Store.new(root)
    expect(described_class.new(store.container).call).to eq([])
  end
end
