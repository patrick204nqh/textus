require "spec_helper"
require "stringio"

RSpec.describe "textus/3 CLI command renames" do
  def run_cli(argv)
    stdin = StringIO.new
    stdout = StringIO.new
    stderr = StringIO.new
    code = Textus::CLI.run(argv, stdin: stdin, stdout: stdout, stderr: stderr)
    { code: code, stdout: stdout.string, stderr: stderr.string }
  end

  it "rejects `textus mv` with rename hint to `key mv`" do
    out = run_cli(%w[mv working.x working.y --as=human])
    expect(JSON.parse(out[:stdout])["code"]).to eq("command_renamed")
    expect(out[:stderr]).to match(/mv.*key mv/)
  end

  it "rejects `textus refresh-stale` with rename hint to `refresh stale`" do
    out = run_cli(%w[refresh-stale])
    expect(out[:stderr]).to match(/refresh-stale.*refresh stale/)
  end

  it "rejects `textus policy list` with rename hint to `rule list`" do
    out = run_cli(%w[policy list])
    expect(out[:stderr]).to match(/policy list.*rule list/)
  end

  it "rejects `textus policy explain` with rename hint to `rule explain`" do
    out = run_cli(["policy", "explain", "key.x"])
    expect(out[:stderr]).to match(/policy explain.*rule explain/)
  end

  it "rejects `textus key migrate` with rename hint to `key normalize`" do
    out = run_cli(%w[key migrate])
    expect(out[:stderr]).to match(/key migrate.*key normalize/)
  end
end
