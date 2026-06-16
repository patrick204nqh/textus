# rubocop:disable Style/GlobalVars
require "spec_helper"
require "stringio"

RSpec.describe ":proposal_rejected event and store.reject" do
  include_context "textus_store_fixture"

  before do
    store_from_manifest(
      root,
      lanes: %w[identity proposals],
      files: {
        "steps/observe/log_reject.rb" => <<~RUBY,
          $textus_event_log ||= []

          Class.new(Textus::Step::Observe) do
            on :proposal_rejected

            def call(key:, target_key:, **)
              $textus_event_log << [:proposal_rejected, key, target_key]
            end

          end
        RUBY

        "steps/observe/log_delete.rb" => <<~RUBY,
          $textus_event_log ||= []
          Class.new(Textus::Step::Observe) do
            on :entry_deleted

            def call(key:, **)
              $textus_event_log << [:entry_deleted, key]
            end
          end
        RUBY
      },
      manifest: <<~YAML,
        version: textus/3
        lanes:
          - { name: identity, kind: canon }
          - { name: proposals,   kind: queue }
        entries:
          - { key: identity.target, path: identity/target.md, lane: identity, kind: leaf}

          - { key: proposals.draft,    path: data/proposals/draft.md,    lane: proposals, kind: leaf}

      YAML
    )
    $textus_event_log = []
  end

  after do
    $textus_event_log = nil
  end

  it "rejects the proposal, returns result, and deletes the entry" do
    store = Textus::Store.new(root)
    store.as("agent").put(
      "proposals.draft",
      meta: { "name" => "draft", "proposal" => { "target_key" => "identity.target", "action" => "put" } },
      body: "proposed body",
    )
    result = store.as("human").reject("proposals.draft")
    expect(result["rejected"]).to eq("proposals.draft")
    expect(result["target_key"]).to eq("identity.target")
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
        lanes: %w[identity proposals],
        manifest: <<~YAML,
          version: textus/3
          lanes:
            - { name: identity, kind: canon }
            - { name: proposals,   kind: queue }
          entries:
            - { key: identity.t, path: identity/t.md, lane: identity, kind: leaf}

            - { key: proposals.d,   path: data/proposals/d.md,   lane: proposals, kind: leaf}

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
      exit_code = Textus::Surfaces::CLI.run(
        ["--root=#{cli_root}", "reject", "proposals.d", "--as=human"],
        stdin: StringIO.new(""), stdout: stdout, stderr: stderr, cwd: cli_dir,
      )
      expect(exit_code).to eq(0), "stderr: #{stderr.string}\nstdout: #{stdout.string}"
      payload = JSON.parse(stdout.string.strip)
      expect(payload["rejected"]).to eq("proposals.d")
      expect(payload["target_key"]).to eq("identity.t")
    end
  end

  # Regression: store.reject must accept a proposal in any zone declaring
  # `kind: queue` (regardless of name), and refuse in a non-queue zone.
  # Detection keys off the declared zone kind (`in_proposal_zone?` =>
  # `declared_kind == :queue`), not the zone name or its writers. (Historically
  # a hardcoded `zone == "pending"` check, then a writer-signal heuristic;
  # 0.30.0 made the declared kind authoritative.)
  describe "declared-kind proposal-zone detection" do
    it "accepts a proposal in a zone declaring kind: queue (named 'proposals')" do
      FileUtils.mkdir_p(File.join(root, "data/identity"))
      FileUtils.mkdir_p(File.join(root, "data/proposals"))
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/3
        lanes:
          - { name: identity, kind: canon }
          - { name: proposals,   kind: queue }
        entries:
          - { key: identity.target, path: identity/target.md, lane: identity, kind: leaf}

          - { key: proposals.draft,    path: data/proposals/draft.md,    lane: proposals, kind: leaf}

      YAML

      store = Textus::Store.new(root)
      store.as("agent").put(
        "proposals.draft",
        meta: { "name" => "draft", "proposal" => { "target_key" => "identity.target", "action" => "put" } },
        body: "proposed body",
      )

      result = store.as("human").reject("proposals.draft")
      expect(result["rejected"]).to eq("proposals.draft")
      expect(result["target_key"]).to eq("identity.target")
      expect(store.as(Textus::Role::DEFAULT).get("proposals.draft")).to be_nil
    end

    it "refuses: a zone declaring kind: canon is not a proposal zone (even if named 'pending')" do
      # Declared-kind check: the zone is not kind: queue, so it is not a proposal
      # zone and reject must refuse — regardless of the zone's name.
      FileUtils.mkdir_p(File.join(root, "data/identity"))
      FileUtils.mkdir_p(File.join(root, "data/pending"))
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/3
        lanes:
          - { name: identity, kind: canon }
          - { name: pending,  kind: canon }
        entries:
          - { key: identity.target, path: identity/target.md, lane: identity, kind: leaf}

          - { key: pending.draft,   path: pending/draft.md,   lane: pending, kind: leaf}

      YAML

      store = Textus::Store.new(root)
      store.as("human").put(
        "pending.draft",
        meta: { "name" => "draft", "proposal" => { "target_key" => "identity.target", "action" => "put" } },
        body: "x",
      )
      expect { store.as("human").reject("pending.draft") }
        .to raise_error(Textus::ProposalError, /not in a proposal zone/)
    end
  end
end
# rubocop:enable Style/GlobalVars
