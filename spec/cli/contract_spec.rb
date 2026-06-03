require "spec_helper"
require "stringio"

RSpec.describe "Textus::CLI verb return-value contract" do
  def with_store
    Dir.mktmpdir do |root|
      textus = File.join(root, ".textus")
      FileUtils.mkdir_p(File.join(textus, "zones", "knowledge"))
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

  it "fetch all on an empty store returns 0 (was nil → TypeError, #61)" do
    with_store do |root|
      code, _stdout, _stderr = run_cli(%w[fetch all --prefix=knowledge --as=automation], cwd: root)
      expect(code).to be_an(Integer)
      expect(code).to eq(0)
    end
  end

  it "every registered verb returns an Integer from a no-op invocation" do
    with_store do |root|
      Textus::CLI.verbs.each_key do |verb|
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
      "build" => Textus::CLI::Verb::Build,
      "deps" => Textus::CLI::Verb::GenDeps,
      "doctor" => Textus::CLI::Verb::Doctor,
      "freshness" => Textus::CLI::Verb::GenFreshness,
      "get" => Textus::CLI::Verb::Get,
      "hook" => Textus::CLI::Group::Hook,
      "init" => Textus::CLI::Verb::Init,
      "boot" => Textus::CLI::Verb::Boot,
      "key" => Textus::CLI::Group::Key,
      "list" => Textus::CLI::Verb::GenList,
      "mcp" => Textus::CLI::Group::MCP,
      "published" => Textus::CLI::Verb::GenPublished,
      "pulse" => Textus::CLI::Verb::GenPulse,
      "propose" => Textus::CLI::Verb::GenPropose,
      "put" => Textus::CLI::Verb::Put,
      "rdeps" => Textus::CLI::Verb::GenRdeps,
      "migrate" => Textus::CLI::Verb::GenMigrate,
      "fetch" => Textus::CLI::Group::Fetch,
      "reject" => Textus::CLI::Verb::GenReject,
      "retain" => Textus::CLI::Verb::GenRetain,
      "rule" => Textus::CLI::Group::Rule,
      "schema" => Textus::CLI::Group::Schema,
      "where" => Textus::CLI::Verb::GenWhere,
      "zone" => Textus::CLI::Group::Zone,
    }
    expect(actual).to eq(expected)
  end

  it "verb ordering is stable (alphabetical by command_name)" do
    keys = Textus::CLI.verbs.keys
    expect(keys).to eq(keys.sort)
  end

  it "group subcommand tables are auto-derived from parent_group" do
    expect(Textus::CLI::Group::Hook.subcommands).to eq(
      "list" => Textus::CLI::Verb::Hooks,
      "run" => Textus::CLI::Verb::HookRun,
    )
    expect(Textus::CLI::Group::Key.subcommands).to eq(
      "delete" => Textus::CLI::Verb::GenDelete,
      "delete-prefix" => Textus::CLI::Verb::GenKeyDeletePrefix,
      "mv" => Textus::CLI::Verb::Mv,
      "uid" => Textus::CLI::Verb::GenUid,
    )
    expect(Textus::CLI::Group::Rule.subcommands).to eq(
      "explain" => Textus::CLI::Verb::GenRuleExplain,
      "lint" => Textus::CLI::Verb::GenRuleLint,
      "list" => Textus::CLI::Verb::GenRuleList,
    )
    expect(Textus::CLI::Group::Zone.subcommands).to eq(
      "mv" => Textus::CLI::Verb::GenZoneMv,
    )
    expect(Textus::CLI::Group::Schema.subcommands).to eq(
      "diff" => Textus::CLI::Verb::SchemaDiff,
      "init" => Textus::CLI::Verb::SchemaInit,
      "migrate" => Textus::CLI::Verb::SchemaMigrate,
      "show" => Textus::CLI::Verb::GenSchemaShow,
    )
  end
end
