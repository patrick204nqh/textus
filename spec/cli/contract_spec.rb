require "spec_helper"
require "stringio"
require "tmpdir"
require "fileutils"

RSpec.describe "Textus::CLI verb return-value contract" do
  def with_store
    Dir.mktmpdir do |root|
      textus = File.join(root, ".textus")
      FileUtils.mkdir_p(File.join(textus, "zones", "working"))
      File.write(File.join(textus, "manifest.yaml"), <<~YAML)
        version: textus/3
        zones:
          - { name: working, write_policy: [human] }
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

  it "refresh stale on an empty store returns 0 (was nil → TypeError, #61)" do
    with_store do |root|
      code, _stdout, _stderr = run_cli(%w[refresh stale --prefix=working --as=runner], cwd: root)
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
    expected = {
      "accept" => Textus::CLI::Verb::Accept,
      "audit" => Textus::CLI::Verb::Audit,
      "blame" => Textus::CLI::Verb::Blame,
      "build" => Textus::CLI::Verb::Build,
      "delete" => Textus::CLI::Verb::Delete,
      "deps" => Textus::CLI::Verb::Deps,
      "doctor" => Textus::CLI::Verb::Doctor,
      "freshness" => Textus::CLI::Verb::Freshness,
      "get" => Textus::CLI::Verb::Get,
      "hook" => Textus::CLI::Group::Hook,
      "init" => Textus::CLI::Verb::Init,
      "boot" => Textus::CLI::Verb::Boot,
      "key" => Textus::CLI::Group::Key,
      "list" => Textus::CLI::Verb::List,
      "published" => Textus::CLI::Verb::Published,
      "pulse" => Textus::CLI::Verb::Pulse,
      "put" => Textus::CLI::Verb::Put,
      "rdeps" => Textus::CLI::Verb::Rdeps,
      "refresh" => Textus::CLI::Group::Refresh,
      "reject" => Textus::CLI::Verb::Reject,
      "rule" => Textus::CLI::Group::Rule,
      "schema" => Textus::CLI::Group::Schema,
      "where" => Textus::CLI::Verb::Where,
    }
    expect(Textus::CLI.verbs).to eq(expected)
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
      "mv" => Textus::CLI::Verb::Mv,
      "uid" => Textus::CLI::Verb::Uid,
    )
    expect(Textus::CLI::Group::Rule.subcommands).to eq(
      "explain" => Textus::CLI::Verb::RuleExplain,
      "list" => Textus::CLI::Verb::RuleList,
    )
    expect(Textus::CLI::Group::Schema.subcommands).to eq(
      "diff" => Textus::CLI::Verb::SchemaDiff,
      "init" => Textus::CLI::Verb::SchemaInit,
      "migrate" => Textus::CLI::Verb::SchemaMigrate,
      "show" => Textus::CLI::Verb::Schema,
    )
  end
end
