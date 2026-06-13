require "spec_helper"
require "stringio"

RSpec.describe "Textus::CLI verb return-value contract" do
  def with_store
    Dir.mktmpdir do |root|
      textus = File.join(root, ".textus")
      FileUtils.mkdir_p(File.join(textus, "data", "knowledge"))
      File.write(File.join(textus, "manifest.yaml"), <<~YAML)
        version: textus/3
        zones:
          - { name: knowledge, kind: canon }
        entries: []
      YAML
      yield root
    end
  end

  def run_cli(argv, cwd:)
    out = StringIO.new
    err = StringIO.new
    code = Textus::CLI.run(argv, stdin: StringIO.new, stdout: out, stderr: err, cwd: cwd)
    [code, out.string, err.string]
  end

  it "every registered verb returns an Integer from a no-op invocation" do
    with_store do |root|
      Textus::CLI.verbs.each_key do |verb|
        next if verb == "watch" # the daemon blocks forever by design; it has no no-op invocation

        code, = run_cli([verb], cwd: root)
        expect(code).to be_an(Integer),
                        "verb `textus #{verb}` returned #{code.inspect} (expected Integer)"
      end
    end
  end

  it "the auto-derived verb table matches the prior surface exactly" do # rubocop:disable RSpec/ExampleLength
    actual = Textus::CLI.verbs # triggers Runner.install! so Verb::GenWhere exists
    expected = {
      "accept" => Textus::CLI::Verb::GenAccept,
      "audit" => Textus::CLI::Verb::GenAudit,
      "blame" => Textus::CLI::Verb::GenBlame,
      "capabilities" => Textus::CLI::Verb::GenCapabilities,
      "deps" => Textus::CLI::Verb::GenDeps,
      "doctor" => Textus::CLI::Verb::Doctor,
      "enqueue" => Textus::CLI::Verb::GenEnqueue,
      "get" => Textus::CLI::Verb::Get,
      "init" => Textus::CLI::Verb::Init,
      "boot" => Textus::CLI::Verb::GenBoot,
      "data" => Textus::CLI::Group::Data,
      "key" => Textus::CLI::Group::Key,
      "list" => Textus::CLI::Verb::GenList,
      "mcp" => Textus::CLI::Group::MCP,
      "published" => Textus::CLI::Verb::GenPublished,
      "pulse" => Textus::CLI::Verb::GenPulse,
      "propose" => Textus::CLI::Verb::GenPropose,
      "put" => Textus::CLI::Verb::Put,
      "rdeps" => Textus::CLI::Verb::GenRdeps,
      "reject" => Textus::CLI::Verb::GenReject,
      "rule" => Textus::CLI::Group::Rule,
      "schema" => Textus::CLI::Group::Schema,
      "drain" => Textus::CLI::Verb::GenDrain,
      "jobs" => Textus::CLI::Verb::GenJobs,
      "watch" => Textus::CLI::Verb::Watch,
      "where" => Textus::CLI::Verb::GenWhere,
    }
    expect(actual).to eq(expected)
  end

  it "verb ordering is stable (alphabetical by command_name)" do
    keys = Textus::CLI.verbs.keys
    expect(keys).to eq(keys.sort)
  end

  it "group subcommand tables are auto-derived from parent_group" do
    expect(Textus::CLI::Group::Key.subcommands).to eq(
      "delete" => Textus::CLI::Verb::GenKeyDelete,
      "delete-prefix" => Textus::CLI::Verb::GenKeyDeletePrefix,
      "mv" => Textus::CLI::Verb::GenKeyMv,
      "mv-prefix" => Textus::CLI::Verb::GenKeyMvPrefix,
      "uid" => Textus::CLI::Verb::GenUid,
    )
    expect(Textus::CLI::Group::Rule.subcommands).to eq(
      "explain" => Textus::CLI::Verb::GenRuleExplain,
      "lint" => Textus::CLI::Verb::GenRuleLint,
      "list" => Textus::CLI::Verb::GenRuleList,
    )
    expect(Textus::CLI::Group::Data.subcommands).to eq(
      "mv" => Textus::CLI::Verb::GenDataMv,
    )
    expect(Textus::CLI::Group::Schema.subcommands).to eq(
      "diff" => Textus::CLI::Verb::SchemaDiff,
      "init" => Textus::CLI::Verb::SchemaInit,
      "migrate" => Textus::CLI::Verb::SchemaMigrate,
      "show" => Textus::CLI::Verb::GenSchemaShow,
    )
  end
end
