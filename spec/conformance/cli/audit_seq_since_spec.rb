require "spec_helper"
require "stringio"

RSpec.describe "textus audit --seq-since" do
  def with_store
    Dir.mktmpdir do |root|
      textus = File.join(root, ".textus")
      FileUtils.mkdir_p(File.join(textus, "data", "knowledge"))
      File.write(File.join(textus, "manifest.yaml"), <<~YAML)
        version: textus/4
        lanes: [{ name: knowledge, kind: canon }]
        entries: []
      YAML
      yield root, textus
    end
  end

  def run_cli(argv, cwd:)
    out = StringIO.new
    err = StringIO.new
    code = Textus::Surfaces::CLI.run(argv, stdin: StringIO.new, stdout: out, stderr: err, cwd: cwd)
    [code, out.string, err.string]
  end

  it "returns only rows with seq > N" do
    with_store do |root, textus|
      log = Textus::Ports::AuditLog.new(textus)
      log.append(role: "human", verb: "put", key: "a", etag_before: nil, etag_after: "e1")
      log.append(role: "human", verb: "put", key: "b", etag_before: nil, etag_after: "e2")
      log.append(role: "human", verb: "put", key: "c", etag_before: nil, etag_after: "e3")

      code, stdout, = run_cli(%w[audit --seq-since=1], cwd: root)
      expect(code).to eq(0)
      env = JSON.parse(stdout)
      seqs = env["rows"].map { |r| r["seq"] }
      expect(seqs).to eq([2, 3])
    end
  end

  it "raises CursorExpired when seq is below min_available_seq" do
    with_store do |root, textus|
      # Simulate rotation having dropped seqs 1..10
      FileUtils.mkdir_p(Textus::StoreGeometry.new(textus).audit_dir_path)
      File.write(File.join(Textus::StoreGeometry.new(textus).audit_dir_path, "audit.log.1.meta.json"),
                 JSON.generate({ "min_seq" => 11, "max_seq" => 20, "rotated_at" => Time.now.utc.iso8601 }))
      File.write(File.join(Textus::StoreGeometry.new(textus).audit_dir_path, "audit.log.1"), "") # rotated file exists (content not needed for this test)
      log = Textus::Ports::AuditLog.new(textus)
      # Append one fresh row so latest_seq > 20
      log.append(role: "human", verb: "put", key: "a", etag_before: nil, etag_after: "e1")

      code, _stdout, stderr = run_cli(%w[audit --seq-since=3], cwd: root)
      expect(code).not_to eq(0)
      expect(stderr).to match(/cursor.*expired/i)
    end
  end

  it "reads across rotated files in ascending seq order" do
    with_store do |root, textus|
      # Manually craft a rotated file + sidecar + active log to simulate post-rotation state.
      ts = Time.now.utc.iso8601
      row1 = JSON.generate({
                             "seq" => 1, "ts" => ts, "role" => "human", "verb" => "put",
                             "key" => "old1", "etag_before" => nil, "etag_after" => "e"
                           })
      row2 = JSON.generate({
                             "seq" => 2, "ts" => ts, "role" => "human", "verb" => "put",
                             "key" => "old2", "etag_before" => nil, "etag_after" => "e"
                           })
      FileUtils.mkdir_p(Textus::StoreGeometry.new(textus).audit_dir_path)
      File.write(File.join(Textus::StoreGeometry.new(textus).audit_dir_path, "audit.log.1"),
                 [row1, row2].join("\n") + "\n")
      File.write(File.join(Textus::StoreGeometry.new(textus).audit_dir_path, "audit.log.1.meta.json"),
                 JSON.generate({ "min_seq" => 1, "max_seq" => 2, "rotated_at" => Time.now.utc.iso8601 }))
      log = Textus::Ports::AuditLog.new(textus)
      log.append(role: "human", verb: "put", key: "new1", etag_before: nil, etag_after: "e")
      # active log now has seq=3

      code, stdout, = run_cli(%w[audit --seq-since=0], cwd: root)
      expect(code).to eq(0)
      env = JSON.parse(stdout)
      expect(env["rows"].map { |r| r["seq"] }).to eq([1, 2, 3])
      expect(env["rows"].map { |r| r["key"] }).to eq(%w[old1 old2 new1])
    end
  end
end
