require "spec_helper"
require "tmpdir"
require "fileutils"
require "stringio"
require "json"

RSpec.describe "textus audit-rewrite-legacy-roles" do
  let(:tmp) { Dir.mktmpdir }
  let(:root) { File.join(tmp, ".textus") }
  let(:log_path) { File.join(root, "audit.log") }

  before { FileUtils.mkdir_p(root) }
  after { FileUtils.remove_entry(tmp) }

  def run_cli(*args)
    stdin = StringIO.new
    stdout = StringIO.new
    stderr = StringIO.new
    code = Textus::CLI.run(["--root=#{root}", *args],
                           stdin: stdin, stdout: stdout, stderr: stderr, cwd: tmp)
    { code: code, stdout: stdout.string, stderr: stderr.string }
  end

  def write_rows(rows)
    File.write(log_path, rows.map { |r| JSON.generate(r) }.join("\n") + "\n")
  end

  def read_rows
    File.readlines(log_path).map { |l| JSON.parse(l) }
  end

  it "rewrites ai→agent, script→runner, build→builder in place" do
    write_rows(
      [{ "ts" => "2026-01-01", "role" => "ai",     "verb" => "put", "key" => "k", "etag_before" => nil, "etag_after" => "a" },
       { "ts" => "2026-01-02", "role" => "script", "verb" => "put", "key" => "k", "etag_before" => nil, "etag_after" => "b" },
       { "ts" => "2026-01-03", "role" => "build",  "verb" => "put", "key" => "k", "etag_before" => nil, "etag_after" => "c" },
       { "ts" => "2026-01-04", "role" => "human",  "verb" => "put", "key" => "k", "etag_before" => nil, "etag_after" => "d" }],
    )
    run_cli("audit-rewrite-legacy-roles")
    rows = read_rows.reject { |r| r["verb"] == "audit-rewrite-legacy-roles-marker" }
    expect(rows.map { |r| r["role"] }).to eq(%w[agent runner builder human])
  end

  it "appends a marker line documenting the rewrite" do
    write_rows([{ "ts" => "x", "role" => "ai", "verb" => "put", "key" => "k", "etag_before" => nil, "etag_after" => "a" }])
    run_cli("audit-rewrite-legacy-roles")
    marker = read_rows.last
    expect(marker["verb"]).to eq("audit-rewrite-legacy-roles-marker")
    expect(marker["details"]).to include("rewrote" => 1)
  end

  it "is idempotent — second run is a no-op (marker present already)" do
    write_rows([{ "ts" => "x", "role" => "ai", "verb" => "put", "key" => "k", "etag_before" => nil, "etag_after" => "a" }])
    run_cli("audit-rewrite-legacy-roles")
    rows_after_first = read_rows
    run_cli("audit-rewrite-legacy-roles")
    expect(read_rows).to eq(rows_after_first)
  end

  it "is a no-op on a clean log (no marker appended)" do
    write_rows([{ "ts" => "x", "role" => "human", "verb" => "put", "key" => "k", "etag_before" => nil, "etag_after" => "a" }])
    before = File.read(log_path)
    run_cli("audit-rewrite-legacy-roles")
    expect(File.read(log_path)).to eq(before)
  end

  it "exits 0 with an envelope reporting counts" do
    write_rows([{ "ts" => "x", "role" => "ai", "verb" => "put", "key" => "k", "etag_before" => nil, "etag_after" => "a" }])
    out = run_cli("audit-rewrite-legacy-roles")
    expect(out[:code]).to eq(0)
    env = JSON.parse(out[:stdout])
    expect(env["ok"]).to be true
    expect(env["rewrote"]).to eq(1)
  end
end
