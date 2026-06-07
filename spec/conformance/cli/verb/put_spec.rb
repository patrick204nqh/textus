require "spec_helper"
require "stringio"

# Guard (ADR 0089): `textus put KEY --stdin` must store the piped JSON body,
# returning uid+etag. CLI::Verb::Put owns its own stdin parsing — the contract
# carries no `cli_stdin` facet — so this round-trip confirms the hand-authored
# verb path is correct regardless of what the contract DSL does or doesn't say.
RSpec.describe "textus put KEY --stdin (ADR 0089 — verb owns stdin)" do
  include_context "textus_store_fixture"

  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }

  before { minimal_store(root) }

  def run(argv, stdin_body: "")
    Textus::CLI.run(
      argv,
      stdin: StringIO.new(stdin_body),
      stdout: stdout,
      stderr: stderr,
      cwd: tmp,
    )
  end

  it "stores the piped JSON and exits 0, returning uid and etag" do
    payload = JSON.generate("_meta" => {}, "body" => "hello\n")
    rc = run(
      ["--root=#{root}", "put", "knowledge.foo", "--stdin"],
      stdin_body: payload,
    )
    expect(rc).to eq(0), "stderr: #{stderr.string}\nstdout: #{stdout.string}"
    result = JSON.parse(stdout.string)
    expect(result).to include("uid", "etag")
  end
end
