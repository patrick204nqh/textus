require "spec_helper"
require "stringio"

RSpec.describe "textus pulse CLI" do
  def with_store
    Dir.mktmpdir do |root|
      textus = File.join(root, ".textus")
      FileUtils.mkdir_p(File.join(textus, "data", "knowledge"))
      FileUtils.mkdir_p(File.join(textus, "data", "review"))
      File.write(File.join(textus, "manifest.yaml"), <<~YAML)
        version: textus/3
        zones:
          - { name: knowledge, kind: canon }
          - { name: review,  kind: canon }
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

      Textus::Ports::AuditLog.new(textus).append(
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

  it "advances its own cursor across calls when --since is omitted" do
    with_store do |root, textus|
      _code, out1 = run_cli(%w[pulse --as=agent], cwd: root)
      first_cursor = JSON.parse(out1)["cursor"]

      Textus::Ports::AuditLog.new(textus).append(
        role: "human",
        verb: "put",
        key: "knowledge.note",
        etag_before: nil,
        etag_after: "e2",
      )

      _code, out2 = run_cli(%w[pulse --as=agent], cwd: root)
      out2_parsed = JSON.parse(out2)
      expect(out2_parsed["cursor"]).to be > first_cursor
      expect(out2_parsed["changed"].map { |c| c["key"] }).to include("knowledge.note")

      _code, out3 = run_cli(%w[pulse --as=agent], cwd: root)
      out3_parsed = JSON.parse(out3)
      expect(out3_parsed["changed"]).to eq([])
      expect(out3_parsed["cursor"]).to eq(out2_parsed["cursor"])
    end
  end

  it "stays stateless when --since is given explicitly" do
    with_store do |root, _|
      _code, out = run_cli(%w[pulse --as=agent --since=0], cwd: root)
      expect(JSON.parse(out)["cursor"]).to be_a(Integer)
    end
  end
end
