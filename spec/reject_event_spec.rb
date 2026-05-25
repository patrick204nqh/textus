# rubocop:disable Style/GlobalVars
require "spec_helper"
require "fileutils"
require "tmpdir"
require "stringio"
require "json"

RSpec.describe ":proposal_rejected event and store.reject" do
  let(:tmp)  { Dir.mktmpdir }
  let(:root) { File.join(tmp, ".textus") }

  before do
    FileUtils.mkdir_p(File.join(root, "zones/review"))
    FileUtils.mkdir_p(File.join(root, "zones/identity"))
    FileUtils.mkdir_p(File.join(root, "hooks"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: identity, write_policy: [human] }
        - { name: review,   write_policy: [agent, human] }
      entries:
        - { key: identity.target, path: identity/target.md, zone: identity }
        - { key: review.draft,    path: review/draft.md,    zone: review }
    YAML
    File.write(File.join(root, "hooks/log.rb"), <<~RUBY)
      $textus_event_log ||= []
      Textus.on(:proposal_rejected, :log_reject) do |key:, target_key:, store:|
        $textus_event_log << [:proposal_rejected, key, target_key]
      end
      Textus.on(:entry_deleted, :log_delete) { |key:, store:| $textus_event_log << [:entry_deleted, key] }
    RUBY
    $textus_event_log = []
  end

  after do
    FileUtils.remove_entry(tmp)
    $textus_event_log = nil
  end

  it "fires :reject with review key and proposal target_key, then deletes the entry" do
    store = Textus::Store.new(root)
    store.put("review.draft",
              meta: { "name" => "draft", "proposal" => { "target_key" => "identity.target", "action" => "put" } },
              body: "proposed body", as: "agent")
    $textus_event_log.clear
    result = store.reject("review.draft", as: "human")
    expect(result["rejected"]).to eq("review.draft")
    expect(result["target_key"]).to eq("identity.target")
    reject_events = $textus_event_log.select { |e| e[0] == :proposal_rejected }
    expect(reject_events.length).to eq(1)
    expect(reject_events.first[1]).to eq("review.draft")
    expect(reject_events.first[2]).to eq("identity.target")
    expect { store.get("review.draft") }.to raise_error(Textus::UnknownKey)
  end

  it "refuses to reject a non-review entry" do
    store = Textus::Store.new(root)
    store.put("identity.target", meta: { "name" => "target" }, body: "x", as: "human")
    expect { store.reject("identity.target", as: "human") }
      .to raise_error(Textus::ProposalError, /not in a proposal zone/)
  end

  it "refuses to reject when entry has no proposal block" do
    store = Textus::Store.new(root)
    store.put("review.draft", meta: { "name" => "draft" }, body: "x", as: "agent")
    expect { store.reject("review.draft", as: "human") }
      .to raise_error(Textus::ProposalError, /no proposal/)
  end

  context "CLI: textus reject" do
    def build_cli_store!(root)
      FileUtils.mkdir_p(File.join(root, "zones/review"))
      FileUtils.mkdir_p(File.join(root, "zones/identity"))
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/3
        zones:
          - { name: identity, write_policy: [human] }
          - { name: review,   write_policy: [agent, human] }
        entries:
          - { key: identity.t, path: identity/t.md, zone: identity }
          - { key: review.d,   path: review/d.md,   zone: review }
      YAML
      store = Textus::Store.new(root)
      store.put("review.d",
                meta: { "name" => "d", "proposal" => { "target_key" => "identity.t", "action" => "put" } },
                body: "x", as: "agent")
    end

    it "rejects a review entry via CLI and emits JSON" do
      Dir.mktmpdir do |dir|
        cli_root = File.join(dir, ".textus")
        build_cli_store!(cli_root)
        stdout = StringIO.new
        stderr = StringIO.new
        exit_code = Textus::CLI.run(
          ["--root=#{cli_root}", "reject", "review.d", "--as=human"],
          stdin: StringIO.new(""), stdout: stdout, stderr: stderr, cwd: dir,
        )
        expect(exit_code).to eq(0), "stderr: #{stderr.string}\nstdout: #{stdout.string}"
        payload = JSON.parse(stdout.string.strip)
        expect(payload["rejected"]).to eq("review.d")
        expect(payload["target_key"]).to eq("identity.t")
      end
    end
  end
end
# rubocop:enable Style/GlobalVars
