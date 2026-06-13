require "spec_helper"

RSpec.describe "textus mv" do
  include_context "textus_store_fixture"

  let(:store) { Textus::Store.new(root) }

  before do
    FileUtils.mkdir_p(File.join(root, "data/knowledge/notes"))
    FileUtils.mkdir_p(File.join(root, "data/identity/notes"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: knowledge, kind: canon }
        - { name: identity,   kind: canon }
      entries:
        - { key: knowledge.notes, path: knowledge/notes, zone: knowledge, kind: nested}

        - { key: identity.notes,   path: identity/notes,   zone: identity,   kind: nested}

    YAML
  end

  def put_md(key, body: "hi")
    basename = key.split(".").last
    store.as("human").put(key, meta: { "name" => basename }, body: body)
  end

  it "moves an entry within the same zone, preserving uid" do
    env = put_md("knowledge.notes.alpha")
    uid = env.uid
    res = store.as("human").key_mv("knowledge.notes.alpha", "knowledge.notes.beta")
    expect(res["ok"]).to be true
    expect(res["uid"]).to eq(uid)
    expect(File.exist?(File.join(root, "data/knowledge/notes/alpha.md"))).to be false
    expect(File.exist?(File.join(root, "data/knowledge/notes/beta.md"))).to be true
    expect(store.as(Textus::Role::DEFAULT).get("knowledge.notes.beta").uid).to eq(uid)
  end

  it "writes an audit row with verb=mv and top-level structural fields" do
    put_md("knowledge.notes.alpha")
    store.as("human").key_mv("knowledge.notes.alpha", "knowledge.notes.beta")
    expect(store).to have_audit_verb("key_mv")
    parsed = last_audit_row(store)
    expect(parsed["key"]).to eq("knowledge.notes.beta")
    expect(parsed["from_key"]).to eq("knowledge.notes.alpha")
    expect(parsed["to_key"]).to eq("knowledge.notes.beta")
    expect(parsed["uid"]).to match(/\A[a-f0-9]{12,}\z/)
    expect(parsed["extras"]["from_path"]).to end_with("knowledge/notes/alpha.md")
    expect(parsed["extras"]["to_path"]).to end_with("knowledge/notes/beta.md")
  end

  it "refuses cross-zone moves" do
    put_md("knowledge.notes.alpha")
    expect do
      store.as("human").key_mv("knowledge.notes.alpha", "identity.notes.alpha")
    end.to raise_error(Textus::UsageError, /cross-zone/)
  end

  it "refuses to clobber an existing target" do
    put_md("knowledge.notes.alpha")
    put_md("knowledge.notes.beta")
    expect do
      store.as("human").key_mv("knowledge.notes.alpha", "knowledge.notes.beta")
    end.to raise_error(Textus::UsageError, /already exists/)
  end

  it "refuses when the new key fails grammar" do
    put_md("knowledge.notes.alpha")
    expect do
      store.as("human").key_mv("knowledge.notes.alpha", "knowledge.notes.Bad_Name")
    end.to raise_error(Textus::UsageError, /invalid key segment/)
  end

  it "mints a uid if the source had none, so the audit row carries it" do
    src = File.join(root, "data/knowledge/notes/alpha.md")
    File.write(src, "---\nname: alpha\n---\nbody\n")
    expect(store.as(Textus::Role::DEFAULT).get("knowledge.notes.alpha").uid).to be_nil

    res = store.as("human").key_mv("knowledge.notes.alpha", "knowledge.notes.beta")
    expect(res["uid"]).to match(/\A[a-f0-9]{12,}\z/)
    expect(store.as(Textus::Role::DEFAULT).get("knowledge.notes.beta").uid).to eq(res["uid"])

    parsed = last_audit_row(store)
    expect(parsed["uid"]).to eq(res["uid"])
  end

  it "is wired up in the CLI" do
    put_md("knowledge.notes.alpha")
    out = StringIO.new
    err = StringIO.new
    code = Textus::CLI.run(
      ["key", "mv", "knowledge.notes.alpha", "knowledge.notes.beta", "--as=human", "--output=json"],
      stdin: StringIO.new, stdout: out, stderr: err, cwd: File.dirname(root),
    )
    expect(code).to eq(0), "stdout=#{out.string} stderr=#{err.string}"
    payload = JSON.parse(out.string.lines.last)
    expect(payload["ok"]).to be true
    expect(payload["to_key"]).to eq("knowledge.notes.beta")
  end

  # rubocop:disable Style/GlobalVars
  describe ":entry_renamed event" do
    before do
      FileUtils.mkdir_p(File.join(root, "data/knowledge"))
      FileUtils.mkdir_p(File.join(root, "steps/observe"))
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/3
        zones: [{ name: knowledge, kind: canon }]
        entries:
          - { key: knowledge.a, path: knowledge/a.md, zone: knowledge, kind: leaf}

          - { key: knowledge.b, path: knowledge/b.md, zone: knowledge, kind: leaf}

      YAML
      File.write(File.join(root, "steps/observe/log_mv.rb"), <<~RUBY)
        $textus_event_log ||= []

        Class.new(Textus::Step::Observe) do
          on :entry_renamed

          def call(from_key:, to_key:, envelope:, **)
            $textus_event_log << [:entry_renamed, from_key, to_key, envelope.uid]
          end

        end
      RUBY
      File.write(File.join(root, "steps/observe/log_put.rb"), <<~RUBY)
        $textus_event_log ||= []
        Class.new(Textus::Step::Observe) do
          on :entry_written

          def call(key:, **)
            $textus_event_log << [:entry_written, key]
          end

        end
      RUBY
      File.write(File.join(root, "steps/observe/log_delete.rb"), <<~RUBY)
        $textus_event_log ||= []
        Class.new(Textus::Step::Observe) do
          on :entry_deleted

          def call(key:, **)
            $textus_event_log << [:entry_deleted, key]
          end
        end
      RUBY
      $textus_event_log = []
    end

    after { $textus_event_log = nil }

    it "fires :entry_renamed with from_key, to_key, and envelope after a successful mv" do
      store = Textus::Store.new(root)
      store.as("human").put("knowledge.a", meta: { "name" => "a" }, body: "hi")
      $textus_event_log.clear
      store.as("human").key_mv("knowledge.a", "knowledge.b")
      mv_events = $textus_event_log.select { |e| e[0] == :entry_renamed }
      expect(mv_events.length).to eq(1)
      expect(mv_events.first[1]).to eq("knowledge.a")
      expect(mv_events.first[2]).to eq("knowledge.b")
      expect(mv_events.first[3]).to match(/\A[0-9a-f]{16}\z/)
    end

    it "does NOT fire :entry_written or :entry_deleted on mv (entry_renamed is its own signal)" do
      store = Textus::Store.new(root)
      store.as("human").put("knowledge.a", meta: { "name" => "a" }, body: "hi")
      $textus_event_log.clear
      store.as("human").key_mv("knowledge.a", "knowledge.b")
      expect($textus_event_log.map(&:first)).not_to include(:entry_written, :entry_deleted)
    end

    it "does NOT fire :entry_renamed on dry_run" do
      store = Textus::Store.new(root)
      store.as("human").put("knowledge.a", meta: { "name" => "a" }, body: "hi")
      $textus_event_log.clear
      store.as("human").key_mv("knowledge.a", "knowledge.b", dry_run: true)
      expect($textus_event_log).to be_empty
    end

    it "routes :entry_renamed hooks via keys: glob against the destination key" do # rubocop:disable RSpec/ExampleLength
      File.write(File.join(root, "steps/observe/scoped.rb"), <<~RUBY)
        $textus_scoped_log ||= []

        Class.new(Textus::Step::Observe) do
          on :entry_renamed
          match "knowledge.b"

          def call(to_key:, **)
            $textus_scoped_log << [:match, to_key]
          end

        end
      RUBY
      File.write(File.join(root, "steps/observe/scoped_no_match.rb"), <<~RUBY)
        $textus_scoped_log ||= []
        Class.new(Textus::Step::Observe) do
          on :entry_renamed
          match "other.*"

          def call(to_key:, **)
            $textus_scoped_log << [:no_match, to_key]
          end
        end
      RUBY
      $textus_scoped_log = []
      store = Textus::Store.new(root)
      store.as("human").put("knowledge.a", meta: { "name" => "a" }, body: "hi")
      store.as("human").key_mv("knowledge.a", "knowledge.b")
      expect($textus_scoped_log.map(&:first)).to eq([:match])
    ensure
      $textus_scoped_log = nil
    end
  end
  # rubocop:enable Style/GlobalVars
end
