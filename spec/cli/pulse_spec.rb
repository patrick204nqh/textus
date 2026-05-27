require "spec_helper"
require "stringio"
require "tmpdir"
require "json"

RSpec.describe "textus pulse CLI" do
  def with_store
    Dir.mktmpdir do |root|
      textus = File.join(root, ".textus")
      FileUtils.mkdir_p(File.join(textus, "zones", "working"))
      FileUtils.mkdir_p(File.join(textus, "zones", "review"))
      File.write(File.join(textus, "manifest.yaml"), <<~YAML)
        version: textus/3
        zones:
          - { name: working, write_policy: [human] }
          - { name: review,  write_policy: [agent] }
        entries: []
      YAML
      yield root, textus
    end
  end

  def run_cli(argv, cwd:)
    out = StringIO.new
    err = StringIO.new
    code = Textus::CLI.run(argv, stdin: StringIO.new, stdout: out, stderr: err, cwd: cwd)
    [code, out.string, err.string]
  end

  it "emits an envelope with cursor, changed, stale, pending_review, doctor" do
    with_store do |root, _textus|
      code, stdout = run_cli(%w[pulse --since=0], cwd: root)
      expect(code).to eq(0)
      env = JSON.parse(stdout)
      expect(env).to include("cursor", "changed", "stale", "pending_review", "doctor")
    end
  end

  it "advances cursor monotonically across calls" do
    with_store do |root, textus|
      _code, out1 = run_cli(%w[pulse --since=0], cwd: root)
      c1 = JSON.parse(out1)["cursor"]

      Textus::Infra::AuditLog.new(textus).append(
        role: "human",
        verb: "put",
        key: "a",
        etag_before: nil,
        etag_after: "e1",
      )

      _code, out2 = run_cli(%W[pulse --since=#{c1}], cwd: root)
      c2 = JSON.parse(out2)["cursor"]
      expect(c2).to be > c1
    end
  end

  it "defaults --since to 0 when omitted" do
    with_store do |root, _|
      code, stdout = run_cli(%w[pulse], cwd: root)
      expect(code).to eq(0)
      expect(JSON.parse(stdout)).to have_key("cursor")
    end
  end
end
