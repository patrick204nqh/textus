require "spec_helper"
require "stringio"

RSpec.describe "Textus::Surface::CLI verb return-value contract" do
  def with_store
    Dir.mktmpdir do |root|
      textus = File.join(root, ".textus")
      FileUtils.mkdir_p(File.join(textus, "data", "knowledge"))
      File.write(File.join(textus, "manifest.yaml"), <<~YAML)
        version: textus/4
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
    code = Textus::Surface::CLI.run(argv, stdin: StringIO.new, stdout: out, stderr: err, cwd: cwd)
    [code, out.string, err.string]
  end

  it "every registered verb returns an Integer from a no-op invocation" do
    with_store do |root|
      Textus::Surface::CLI.verbs.each_key do |verb|
        next if verb == "watch" # the daemon blocks forever by design; it has no no-op invocation

        code, = run_cli([verb], cwd: root)
        expect(code).to be_an(Integer),
                        "verb `textus #{verb}` returned #{code.inspect} (expected Integer)"
      end
    end
  end

  it "the auto-derived verb table matches the prior surface exactly" do # rubocop:disable RSpec/ExampleLength
    actual = Textus::Surface::CLI.verbs # triggers Runner.install! so Verb::GenWhere exists
    expected = {
      "accept" => Textus::Surface::CLI::Verb::GenAccept,
      "audit" => Textus::Surface::CLI::Verb::GenAudit,
      "blame" => Textus::Surface::CLI::Verb::GenBlame,
      "deps" => Textus::Surface::CLI::Verb::GenDeps,
      "diff" => Textus::Surface::CLI::Verb::GenDiff,
      "doctor" => Textus::Surface::CLI::Verb::Doctor,
      "graph" => Textus::Surface::CLI::Verb::GenGraph,
      "enqueue" => Textus::Surface::CLI::Verb::GenEnqueue,
      "get" => Textus::Surface::CLI::Verb::Get,
      "ingest" => Textus::Surface::CLI::Verb::GenIngest,
      "init" => Textus::Surface::CLI::Verb::Init,
      "boot" => Textus::Surface::CLI::Verb::GenBoot,
      "data" => Textus::Surface::CLI::Group::Data,
      "key" => Textus::Surface::CLI::Group::Key,
      "list" => Textus::Surface::CLI::Verb::GenList,
      "mcp" => Textus::Surface::CLI::Group::MCP,
      "published" => Textus::Surface::CLI::Verb::GenPublished,
      "pulse" => Textus::Surface::CLI::Verb::GenPulse,
      "propose" => Textus::Surface::CLI::Verb::GenPropose,
      "put" => Textus::Surface::CLI::Verb::Put,
      "rdeps" => Textus::Surface::CLI::Verb::GenRdeps,
      "reject" => Textus::Surface::CLI::Verb::GenReject,
      "rule" => Textus::Surface::CLI::Group::Rule,
      "schema" => Textus::Surface::CLI::Group::Schema,
      "drain" => Textus::Surface::CLI::Verb::GenDrain,
      "jobs" => Textus::Surface::CLI::Verb::GenJobs,
      "watch" => Textus::Surface::CLI::Verb::Watch,
      "where" => Textus::Surface::CLI::Verb::GenWhere,
    }
    expect(actual).to eq(expected)
  end

  it "verb ordering is stable (alphabetical by command_name)" do
    keys = Textus::Surface::CLI.verbs.keys
    expect(keys).to eq(keys.sort)
  end

  it "group subcommand tables are auto-derived from parent_group" do
    expect(Textus::Surface::CLI::Group::Key.subcommands).to eq(
      "delete" => Textus::Surface::CLI::Verb::GenKeyDelete,
      "delete-prefix" => Textus::Surface::CLI::Verb::GenKeyDeletePrefix,
      "mv" => Textus::Surface::CLI::Verb::GenKeyMv,
      "mv-prefix" => Textus::Surface::CLI::Verb::GenKeyMvPrefix,
      "uid" => Textus::Surface::CLI::Verb::GenUid,
    )
    expect(Textus::Surface::CLI::Group::Rule.subcommands).to eq(
      "explain" => Textus::Surface::CLI::Verb::GenRuleExplain,
      "lint" => Textus::Surface::CLI::Verb::GenRuleLint,
      "list" => Textus::Surface::CLI::Verb::GenRuleList,
      "trace" => Textus::Surface::CLI::Verb::GenRuleTrace,
    )
    expect(Textus::Surface::CLI::Group::Data.subcommands).to eq(
      "mv" => Textus::Surface::CLI::Verb::GenDataMv,
    )
    expect(Textus::Surface::CLI::Group::Schema.subcommands).to eq(
      "diff" => Textus::Surface::CLI::Verb::SchemaDiff,
      "init" => Textus::Surface::CLI::Verb::SchemaInit,
      "migrate" => Textus::Surface::CLI::Verb::SchemaMigrate,
      "show" => Textus::Surface::CLI::Verb::GenSchemaShow,
    )
  end
end
