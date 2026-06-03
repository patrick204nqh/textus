require "spec_helper"
require "stringio"

RSpec.describe Textus::CLI::Runner do
  include_context "textus_store_fixture"

  let(:stdin)  { StringIO.new }
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }

  def run(argv)
    Textus::CLI.run(argv, stdin: stdin, stdout: stdout, stderr: stderr, cwd: tmp)
  end

  before do
    FileUtils.mkdir_p(File.join(root, "zones/knowledge"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: knowledge, kind: canon }
      entries:
        - { key: knowledge.note, path: knowledge/note.md, zone: knowledge, kind: leaf }
    YAML
    File.write(File.join(root, "zones/knowledge/note.md"), "---\nuid: abc123\n---\nhello\n")
  end

  it "generates a top-level Verb subclass for the where contract" do
    klass = Textus::CLI.verbs["where"]
    expect(klass).to be < Textus::CLI::Verb
    expect(klass.command_name).to eq("where")
    expect(klass.parent_group).to be_nil
  end

  it "is idempotent — repeated CLI.verbs calls do not create duplicate where commands" do
    Textus::CLI.verbs
    Textus::CLI.verbs
    wheres = Textus::CLI::Verb.descendants.select do |k|
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
      "zone" => "knowledge",
    )
    expect(payload["path"]).to end_with("zones/knowledge/note.md")
    expect(payload).to have_key("owner")
    expect(stderr.string).to be_empty
  end

  it "errors when the positional key is missing" do
    rc = run(["where"])
    expect(rc).not_to eq(0)
  end

  describe "command_name derivation (ADR 0064)" do
    it "derives command_name from the contract cli_leaf when not set explicitly" do
      klass = Class.new(Textus::CLI::Runner::Base)
      klass.spec = Textus::Read::Get.contract # cli_path "get"
      expect(klass.command_name).to eq("get")
    end

    it "derives the leaf for a grouped verb" do
      klass = Class.new(Textus::CLI::Runner::Base)
      klass.spec = Textus::Read::Uid.contract # cli "key uid"
      expect(klass.command_name).to eq("uid")
    end

    it "still honors an explicit command_name" do
      klass = Class.new(Textus::CLI::Runner::Base)
      klass.spec = Textus::Read::Get.contract
      klass.command_name "custom"
      expect(klass.command_name).to eq("custom")
    end
  end

  describe "Runner.dispatch shaper selection" do
    # rubocop:disable RSpec/VerifiedDoubles
    it "uses cli_response instead of response when cli_response is set" do
      spec = Textus::Contract::Spec.new(
        verb: :where,
        summary: nil,
        args: [],
        surfaces: %i[cli],
        response: ->(_v) { "from_response" },
        cli: nil,
        cli_response: ->(v) { { "cli_shaped" => v } },
      )

      emitted = nil
      session_obj = double("session", where: "raw_value")
      verb_instance = double("verb_instance",
                             positional: [],
                             flag_values: {},
                             session_for: session_obj,
                             emit: nil)
      allow(verb_instance).to receive(:flag_values).and_return({})
      allow(verb_instance).to receive(:emit) { |v| emitted = v }

      Textus::CLI::Runner.dispatch(verb_instance, nil, spec)
      expect(emitted).to eq({ "cli_shaped" => "raw_value" })
    end

    it "falls back to response when cli_response is nil" do
      spec = Textus::Contract::Spec.new(
        verb: :where,
        summary: nil,
        args: [],
        surfaces: %i[cli],
        response: ->(v) { { "from_response" => v } },
        cli: nil,
        cli_response: nil,
      )

      emitted = nil
      session_obj = double("session", where: "raw_value")
      verb_instance = double("verb_instance",
                             positional: [],
                             flag_values: {},
                             session_for: session_obj,
                             emit: nil)
      allow(verb_instance).to receive(:flag_values).and_return({})
      allow(verb_instance).to receive(:emit) { |v| emitted = v }

      Textus::CLI::Runner.dispatch(verb_instance, nil, spec)
      expect(emitted).to eq({ "from_response" => "raw_value" })
    end
    # rubocop:enable RSpec/VerifiedDoubles
  end
end
