require "spec_helper"

RSpec.describe Textus::Surfaces::CLI::Runner do
  include_context "textus_store_fixture"
  include_context "cli invocation"

  before do
    FileUtils.mkdir_p(File.join(root, "data/knowledge"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      lanes:
        - { name: knowledge, kind: canon }
      entries:
        - { key: knowledge.note, path: data/knowledge/note.md, lane: knowledge, kind: leaf }
    YAML
    File.write(File.join(root, "data/knowledge/note.md"), "---\nuid: abc123\n---\nhello\n")
  end

  it "generates a top-level Verb subclass for the where contract" do
    klass = Textus::Surfaces::CLI.verbs["where"]
    expect(klass).to be < Textus::Surfaces::CLI::Verb
    expect(klass.command_name).to eq("where")
    expect(klass.parent_group).to be_nil
  end

  it "is idempotent — repeated CLI.verbs calls do not create duplicate where commands" do
    Textus::Surfaces::CLI.verbs
    Textus::Surfaces::CLI.verbs
    wheres = Textus::Surfaces::CLI::Verb.descendants.select do |k|
      k.command_name == "where" && k.parent_group.nil?
    end
    expect(wheres.size).to eq(1)
  end

  it "dispatches `where KEY` and emits the resolved location" do
    rc = run(["where", "knowledge.note"])
    expect(rc).to eq(0)
    payload = JSON.parse(stdout.string)
    expect(payload).to include(
      "key" => "knowledge.note",
      "lane" => "knowledge",
    )
    expect(payload["path"]).to end_with("data/knowledge/note.md")
    expect(payload).to have_key("owner")
    expect(stderr.string).to be_empty
  end

  it "errors when the positional key is missing" do
    rc = run(["where"])
    expect(rc).not_to eq(0)
  end

  describe "command_name derivation (ADR 0064)" do
    it "derives command_name from the contract cli_leaf when not set explicitly" do
      klass = Class.new(Textus::Surfaces::CLI::Runner::Base)
      klass.spec = Textus::Action::Get.contract # cli_path "get"
      expect(klass.command_name).to eq("get")
    end

    it "derives the leaf for a grouped verb" do
      klass = Class.new(Textus::Surfaces::CLI::Runner::Base)
      klass.spec = Textus::Action::Uid.contract # cli "key uid"
      expect(klass.command_name).to eq("uid")
    end

    it "still honors an explicit command_name" do
      klass = Class.new(Textus::Surfaces::CLI::Runner::Base)
      klass.spec = Textus::Action::Get.contract
      klass.command_name "custom"
      expect(klass.command_name).to eq("custom")
    end
  end

  describe "Runner.dispatch shaper selection" do
    # rubocop:disable RSpec/VerifiedDoubles
    let(:key_arg) do
      Struct.new(:name, :type, :required, :positional, :default, :wire, :cli_default).new(:key, String, true, true, :__unset, "key",
                                                                                          :__unset)
    end

    it "uses the :cli view instead of the default when a :cli view is set" do
      spec = Textus::Contract::Spec.new(
        verb: :where,
        summary: nil,
        args: [key_arg],
        surfaces: %i[cli],
        views: { default: ->(_v, _i) { "from_default" }, cli: ->(v, _i) { { "cli_shaped" => v } } },
        cli: nil,
        around: nil,
        cli_stdin: nil,
      )

      emitted = nil
      verb_instance = double("verb_instance",
                             positional: ["knowledge.note"],
                             flag_values: {},
                             resolved_role: "human",
                             emit: nil)
      allow(verb_instance).to receive(:flag_values).and_return({})
      allow(verb_instance).to receive(:emit) { |v| emitted = v }

      Textus::Surfaces::CLI::Runner.dispatch(verb_instance, store, spec)
      expect(emitted).to be_a(Hash)
    end

    it "falls back to the default view when no :cli view is declared" do
      spec = Textus::Contract::Spec.new(
        verb: :where,
        summary: nil,
        args: [key_arg],
        surfaces: %i[cli],
        views: { default: ->(v, _i) { { "from_default" => v } } },
        cli: nil,
        around: nil,
        cli_stdin: nil,
      )

      emitted = nil
      verb_instance = double("verb_instance",
                             positional: ["knowledge.note"],
                             flag_values: {},
                             resolved_role: "human",
                             emit: nil)
      allow(verb_instance).to receive(:flag_values).and_return({})
      allow(verb_instance).to receive(:emit) { |v| emitted = v }

      Textus::Surfaces::CLI::Runner.dispatch(verb_instance, store, spec)
      expect(emitted).to be_a(Hash)
    end
    # rubocop:enable RSpec/VerifiedDoubles
  end

  describe ".shape (ADR 0067 — the :cli view may see call inputs)" do
    def spec_with(cli:, args: [])
      views = { default: ->(v, _i) { v } }
      views[:cli] = cli if cli
      Textus::Contract::Spec.new(
        verb: :demo, summary: "d", args: args, surfaces: [:cli],
        views: views, cli: nil, around: nil, cli_stdin: nil
      )
    end

    def key_arg
      Textus::Contract::Arg.new(
        name: :key, type: String, required: true, positional: true,
        session_default: nil, description: nil, wire_name: nil, default: nil,
        source: nil, coerce: nil, cli_default: :__unset
      )
    end

    it "passes the result to a one-parameter :cli view (inputs ignored)" do
      spec = spec_with(cli: ->(r, _i) { { "wrapped" => r } })
      expect(Textus::Surfaces::CLI::Runner.shape(spec, "X", {})).to eq("wrapped" => "X")
    end

    it "passes (result, inputs) to a two-parameter :cli view, keyed by arg name" do
      spec = spec_with(cli: ->(r, inputs) { { "key" => inputs[:key], "v" => r } }, args: [key_arg])
      expect(Textus::Surfaces::CLI::Runner.shape(spec, "uidval", { key: "k1" })).to eq("key" => "k1", "v" => "uidval")
    end

    it "falls back to the default view when there is no :cli view" do
      spec = spec_with(cli: nil)
      expect(Textus::Surfaces::CLI::Runner.shape(spec, "X", {})).to eq("X")
    end
  end

  describe "key uid (generated, ADR 0065)" do
    it "dispatches `key uid KEY` and emits {key, uid}" do
      rc = run(["key", "uid", "knowledge.note"])
      expect(rc).to eq(0)
      expect(JSON.parse(stdout.string)).to include("key" => "knowledge.note", "uid" => "abc123")
      expect(stderr.string).to be_empty
    end

    it "no longer keeps a hand-authored uid class" do
      expect(Textus::Surfaces::CLI::Runner::HAND_AUTHORED_VERBS).not_to include(:uid)
    end
  end

  describe "blame (generated, ADR 0065)" do
    it "dispatches `blame KEY` and emits {verb, key, rows}" do
      rc = run(["blame", "knowledge.note"])
      expect(rc).to eq(0)
      expect(JSON.parse(stdout.string)).to include(
        "verb" => "blame", "key" => "knowledge.note", "rows" => [],
      )
      expect(stderr.string).to be_empty
    end

    it "no longer keeps a hand-authored blame class" do
      expect(Textus::Surfaces::CLI::Runner::HAND_AUTHORED_VERBS).not_to include(:blame)
    end
  end
end
