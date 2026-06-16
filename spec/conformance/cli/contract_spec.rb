require "spec_helper"
require "stringio"

RSpec.describe "Textus::Surfaces::CLI verb return-value contract" do
  def with_store
    Dir.mktmpdir do |root|
      textus = File.join(root, ".textus")
      FileUtils.mkdir_p(File.join(textus, "data", "knowledge"))
      File.write(File.join(textus, "manifest.yaml"), <<~YAML)
        version: textus/3
        lanes:
          - { name: knowledge, kind: canon }
        entries: []
      YAML
      yield root
    end
  end

  def run_cli(argv, cwd:)
    out = StringIO.new
    err = StringIO.new
    code = Textus::Surfaces::CLI.run(argv, stdin: StringIO.new, stdout: out, stderr: err, cwd: cwd)
    [code, out.string, err.string]
  end

  it "every registered verb returns an Integer from a no-op invocation" do
    with_store do |root|
      Textus::Surfaces::CLI.verbs.each_key do |verb|
        next if verb == "watch" # the daemon blocks forever by design; it has no no-op invocation

        code, = run_cli([verb], cwd: root)
        expect(code).to be_an(Integer),
                        "verb `textus #{verb}` returned #{code.inspect} (expected Integer)"
      end
    end
  end

  it "the auto-derived verb table matches the prior surface exactly" do # rubocop:disable RSpec/ExampleLength
    actual = Textus::Surfaces::CLI.verbs # triggers Runner.install! so Verb::GenWhere exists
    expected = {
      "accept" => Textus::Surfaces::CLI::Verb::GenAccept,
      "audit" => Textus::Surfaces::CLI::Verb::GenAudit,
      "blame" => Textus::Surfaces::CLI::Verb::GenBlame,
      "deps" => Textus::Surfaces::CLI::Verb::GenDeps,
      "doctor" => Textus::Surfaces::CLI::Verb::Doctor,
      "enqueue" => Textus::Surfaces::CLI::Verb::GenEnqueue,
      "get" => Textus::Surfaces::CLI::Verb::Get,
      "ingest" => Textus::Surfaces::CLI::Verb::GenIngest,
      "init" => Textus::Surfaces::CLI::Verb::Init,
      "boot" => Textus::Surfaces::CLI::Verb::GenBoot,
      "data" => Textus::Surfaces::CLI::Group::Data,
      "key" => Textus::Surfaces::CLI::Group::Key,
      "list" => Textus::Surfaces::CLI::Verb::GenList,
      "mcp" => Textus::Surfaces::CLI::Group::MCP,
      "published" => Textus::Surfaces::CLI::Verb::GenPublished,
      "pulse" => Textus::Surfaces::CLI::Verb::GenPulse,
      "propose" => Textus::Surfaces::CLI::Verb::GenPropose,
      "put" => Textus::Surfaces::CLI::Verb::Put,
      "rdeps" => Textus::Surfaces::CLI::Verb::GenRdeps,
      "reject" => Textus::Surfaces::CLI::Verb::GenReject,
      "rule" => Textus::Surfaces::CLI::Group::Rule,
      "schema" => Textus::Surfaces::CLI::Group::Schema,
      "drain" => Textus::Surfaces::CLI::Verb::GenDrain,
      "jobs" => Textus::Surfaces::CLI::Verb::GenJobs,
      "watch" => Textus::Surfaces::CLI::Verb::Watch,
      "where" => Textus::Surfaces::CLI::Verb::GenWhere,
    }
    expect(actual).to eq(expected)
  end

  it "verb ordering is stable (alphabetical by command_name)" do
    keys = Textus::Surfaces::CLI.verbs.keys
    expect(keys).to eq(keys.sort)
  end

  it "group subcommand tables are auto-derived from parent_group" do
    expect(Textus::Surfaces::CLI::Group::Key.subcommands).to eq(
      "delete" => Textus::Surfaces::CLI::Verb::GenKeyDelete,
      "delete-prefix" => Textus::Surfaces::CLI::Verb::GenKeyDeletePrefix,
      "mv" => Textus::Surfaces::CLI::Verb::GenKeyMv,
      "mv-prefix" => Textus::Surfaces::CLI::Verb::GenKeyMvPrefix,
      "uid" => Textus::Surfaces::CLI::Verb::GenUid,
    )
    expect(Textus::Surfaces::CLI::Group::Rule.subcommands).to eq(
      "explain" => Textus::Surfaces::CLI::Verb::GenRuleExplain,
      "lint" => Textus::Surfaces::CLI::Verb::GenRuleLint,
      "list" => Textus::Surfaces::CLI::Verb::GenRuleList,
    )
    expect(Textus::Surfaces::CLI::Group::Data.subcommands).to eq(
      "mv" => Textus::Surfaces::CLI::Verb::GenDataMv,
    )
    expect(Textus::Surfaces::CLI::Group::Schema.subcommands).to eq(
      "diff" => Textus::Surfaces::CLI::Verb::SchemaDiff,
      "init" => Textus::Surfaces::CLI::Verb::SchemaInit,
      "migrate" => Textus::Surfaces::CLI::Verb::SchemaMigrate,
      "show" => Textus::Surfaces::CLI::Verb::GenSchemaShow,
    )
  end
end
