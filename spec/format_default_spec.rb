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

  it "list works without --format=json" do
    rc, out = run_cli(["list"])
    expect(rc).to eq(0)
    expect { JSON.parse(out.lines.last) }.not_to raise_error
  end

  it "get rejects unsupported formats" do
    rc, = run_cli(["get", "identity.self", "--format=yaml"])
    expect(rc).not_to eq(0)
  end

  it "get still accepts --format=json for back-compat" do
    _rc, out = run_cli(["get", "identity.self", "--format=json"])
    parsed = JSON.parse(out.lines.last)
    expect(parsed["code"]).to eq("unknown_key")
  end
end
