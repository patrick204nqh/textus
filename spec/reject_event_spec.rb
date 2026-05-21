# rubocop:disable Style/GlobalVars
require "spec_helper"
require "fileutils"
require "tmpdir"
require "stringio"
require "json"

RSpec.describe ":reject event and store.reject" do
  let(:tmp)  { Dir.mktmpdir }
  let(:root) { File.join(tmp, ".textus") }

  before do
    FileUtils.mkdir_p(File.join(root, "zones/pending"))
    FileUtils.mkdir_p(File.join(root, "zones/canon"))
    FileUtils.mkdir_p(File.join(root, "hooks"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/2
      zones:
        - { name: canon,   writable_by: [human] }
        - { name: pending, writable_by: [ai, human] }
      entries:
        - { key: canon.target,  path: canon/target.md,    zone: canon }
        - { key: pending.draft, path: pending/draft.md,   zone: pending }
    YAML
    File.write(File.join(root, "hooks/log.rb"), <<~RUBY)
      $textus_event_log ||= []
      Textus.hook(:reject, :log_reject) do |key:, target_key:, store:|
        $textus_event_log << [:reject, key, target_key]
      end
      Textus.hook(:delete, :log_delete) { |key:, store:| $textus_event_log << [:delete, key] }
    RUBY
    $textus_event_log = []
  end

  after do
    FileUtils.remove_entry(tmp)
    $textus_event_log = nil
  end

  it "fires :reject with pending key and proposal target_key, then deletes the entry" do
    store = Textus::Store.new(root)
    store.put("pending.draft",
              meta: { "name" => "draft", "proposal" => { "target_key" => "canon.target", "action" => "put" } },
              body: "proposed body", as: "ai")
    $textus_event_log.clear
    result = store.reject("pending.draft", as: "human")
    expect(result["rejected"]).to eq("pending.draft")
    expect(result["target_key"]).to eq("canon.target")
    reject_events = $textus_event_log.select { |e| e[0] == :reject }
    expect(reject_events.length).to eq(1)
    expect(reject_events.first[1]).to eq("pending.draft")
    expect(reject_events.first[2]).to eq("canon.target")
    expect { store.get("pending.draft") }.to raise_error(Textus::UnknownKey)
  end

  it "refuses to reject a non-pending entry" do
    store = Textus::Store.new(root)
    store.put("canon.target", meta: { "name" => "target" }, body: "x", as: "human")
    expect { store.reject("canon.target", as: "human") }
      .to raise_error(Textus::ProposalError, /not a pending/)
  end

  it "refuses to reject when entry has no proposal block" do
    store = Textus::Store.new(root)
    store.put("pending.draft", meta: { "name" => "draft" }, body: "x", as: "ai")
    expect { store.reject("pending.draft", as: "human") }
      .to raise_error(Textus::ProposalError, /no proposal/)
  end

  context "CLI: textus reject" do
    def build_cli_store!(root)
      FileUtils.mkdir_p(File.join(root, "zones/pending"))
      FileUtils.mkdir_p(File.join(root, "zones/canon"))
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/2
        zones:
          - { name: canon,   writable_by: [human] }
          - { name: pending, writable_by: [ai, human] }
        entries:
          - { key: canon.t,   path: canon/t.md,   zone: canon }
          - { key: pending.d, path: pending/d.md, zone: pending }
      YAML
      store = Textus::Store.new(root)
      store.put("pending.d",
                meta: { "name" => "d", "proposal" => { "target_key" => "canon.t", "action" => "put" } },
                body: "x", as: "ai")
    end

    it "rejects a pending entry via CLI and emits JSON" do
      Dir.mktmpdir do |dir|
        cli_root = File.join(dir, ".textus")
        build_cli_store!(cli_root)
        stdout = StringIO.new
        stderr = StringIO.new
        exit_code = Textus::CLI.run(
          ["--root=#{cli_root}", "reject", "pending.d", "--as=human"],
          stdin: StringIO.new(""), stdout: stdout, stderr: stderr, cwd: dir,
        )
        expect(exit_code).to eq(0), "stderr: #{stderr.string}\nstdout: #{stdout.string}"
        payload = JSON.parse(stdout.string.strip)
        expect(payload["rejected"]).to eq("pending.d")
        expect(payload["target_key"]).to eq("canon.t")
      end
    end
  end
end
# rubocop:enable Style/GlobalVars
