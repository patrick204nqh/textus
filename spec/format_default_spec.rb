require "spec_helper"
require "fileutils"
require "tmpdir"
require "json"
require "stringio"

RSpec.describe "CLI default format" do
  let(:tmp) { Dir.mktmpdir }

  before do
    Textus::Init.run(File.join(tmp, ".textus"))
  end

  after { FileUtils.remove_entry(tmp) }

  def run_cli(argv)
    out = StringIO.new
    rc = Textus::CLI.run(argv, stdin: StringIO.new, stdout: out, stderr: StringIO.new, cwd: tmp)
    [rc, out.string]
  end

  it "list works without --output=json" do
    rc, out = run_cli(["list"])
    expect(rc).to eq(0)
    expect { JSON.parse(out.lines.last) }.not_to raise_error
  end

  it "get rejects unsupported output formats" do
    rc, out = run_cli(["get", "identity.self", "--output=yaml"])
    expect(rc).not_to eq(0)
    parsed = JSON.parse(out.lines.last)
    expect(parsed["code"]).to eq("usage")
  end

  it "get rejects legacy --format flag with FlagRenamed envelope" do
    rc, out = run_cli(["get", "identity.self", "--format=json"])
    expect(rc).not_to eq(0)
    parsed = JSON.parse(out.lines.last)
    expect(parsed["code"]).to eq("flag_renamed")
    expect(parsed["message"]).to match(/--format.*--output/)
  end

  it "get accepts --output=json" do
    _rc, out = run_cli(["get", "identity.self", "--output=json"])
    parsed = JSON.parse(out.lines.last)
    expect(parsed["code"]).to eq("unknown_key")
  end
end
