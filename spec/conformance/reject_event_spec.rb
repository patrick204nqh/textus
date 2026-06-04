# rubocop:disable Style/GlobalVars
require "spec_helper"
require "stringio"

RSpec.describe ":proposal_rejected event and store.reject" do
  include_context "textus_store_fixture"

  before do
    store_from_manifest(
      root,
      zones: %w[identity proposals],
      files: {
        "hooks/log.rb" => <<~RUBY,
          $textus_event_log ||= []
          Textus.hook do |reg|
            reg.on(:proposal_rejected, :log_reject) do |key:, target_key:, **|
              $textus_event_log << [:proposal_rejected, key, target_key]
            end
            reg.on(:entry_deleted, :log_delete) { |key:, **| $textus_event_log << [:entry_deleted, key] }
          end
        RUBY
      },
      manifest: <<~YAML,
        version: textus/3
        zones:
          - { name: identity, kind: canon }
          - { name: proposals,   kind: queue }
        entries:
          - { key: identity.target, path: identity/target.md, zone: identity, kind: leaf}

          - { key: proposals.draft,    path: proposals/draft.md,    zone: proposals, kind: leaf}

      YAML
    )
    $textus_event_log = []
  end

  after do
    $textus_event_log = nil
  end

  it "fires :reject with proposals key and proposal target_key, then deletes the entry" do
    store = Textus::Store.new(root)
    store.as("agent").put(
      "proposals.draft",
      meta: { "name" => "draft", "proposal" => { "target_key" => "identity.target", "action" => "put" } },
      body: "proposed body",
    )
    $textus_event_log.clear
    result = store.as("human").reject("proposals.draft")
    expect(result["rejected"]).to eq("proposals.draft")
    expect(result["target_key"]).to eq("identity.target")
    reject_events = $textus_event_log.select { |e| e[0] == :proposal_rejected }
    expect(reject_events.length).to eq(1)
    expect(reject_events.first[1]).to eq("proposals.draft")
    expect(reject_events.first[2]).to eq("identity.target")
    expect(store.as(Textus::Role::DEFAULT).get("proposals.draft")).to be_nil
  end

  it "refuses to reject a non-proposals entry" do
    store = Textus::Store.new(root)
    store.as("human").put("identity.target", meta: { "name" => "target" }, body: "x")
    expect { store.as("human").reject("identity.target") }
      .to raise_error(Textus::ProposalError, /not in a proposal zone/)
  end

  it "refuses to reject when entry has no proposal block" do
    store = Textus::Store.new(root)
    store.as("agent").put("proposals.draft", meta: { "name" => "draft" }, body: "x")
    expect { store.as("human").reject("proposals.draft") }
      .to raise_error(Textus::ProposalError, /no proposal/)
  end

  context "when invoked via the CLI (textus reject)" do
    # A second store with its own cwd, nested under the shared-context `tmp` so
    # the context's `after` cleans it up (the CLI discovers `.textus` from cwd).
    let(:cli_dir) { File.join(tmp, "cli") }
    let(:cli_root) { File.join(cli_dir, ".textus") }
    let(:cli_store) do
      FileUtils.mkdir_p(cli_dir)
      store_from_manifest(
        cli_root,
        zones: %w[identity proposals],
        manifest: <<~YAML,
          version: textus/3
          zones:
            - { name: identity, kind: canon }
            - { name: proposals,   kind: queue }
          entries:
            - { key: identity.t, path: identity/t.md, zone: identity, kind: leaf}

            - { key: proposals.d,   path: proposals/d.md,   zone: proposals, kind: leaf}

        YAML
      )
    end

    it "rejects a proposals entry via CLI and emits JSON" do
      cli_store.as("agent").put(
        "proposals.d",
        meta: { "name" => "d", "proposal" => { "target_key" => "identity.t", "action" => "put" } },
        body: "x",
      )
      stdout = StringIO.new
      stderr = StringIO.new
      exit_code = Textus::CLI.run(
        ["--root=#{cli_root}", "reject", "proposals.d", "--as=human"],
        stdin: StringIO.new(""), stdout: stdout, stderr: stderr, cwd: cli_dir,
      )
      expect(exit_code).to eq(0), "stderr: #{stderr.string}\nstdout: #{stdout.string}"
      payload = JSON.parse(stdout.string.strip)
      expect(payload["rejected"]).to eq("proposals.d")
      expect(payload["target_key"]).to eq("identity.t")
    end
  end
end
# rubocop:enable Style/GlobalVars
