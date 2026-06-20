require "spec_helper"

RSpec.describe Textus::Action::KeyMv do
  it "moves an entry and returns the renamed keys" do
    Dir.mktmpdir do |tmp|
      Textus::Surface::CLI.run(["--root=#{tmp}/.textus", "init"], stdin: StringIO.new(""), stdout: StringIO.new, stderr: StringIO.new,
                                                                   cwd: tmp)
      store = Textus::Store.new(File.join(tmp, ".textus"))
      ops = store.as("human")
      ops.put("knowledge.notes.alpha", meta: { "name" => "alpha" }, body: "hello")

      result = store.as("human").key_mv("knowledge.notes.alpha",
                                        "knowledge.notes.beta")

      expect(result["ok"]).to be(true)
      expect(result["from_key"]).to eq("knowledge.notes.alpha")
      expect(result["to_key"]).to eq("knowledge.notes.beta")
    end
  end

  it "supports dry_run without writing to disk" do
    Dir.mktmpdir do |tmp|
      Textus::Surface::CLI.run(["--root=#{tmp}/.textus", "init"], stdin: StringIO.new(""), stdout: StringIO.new, stderr: StringIO.new,
                                                                   cwd: tmp)
      store = Textus::Store.new(File.join(tmp, ".textus"))
      ops = store.as("human")
      ops.put("knowledge.notes.alpha", meta: { "name" => "alpha" }, body: "hello")

      result = store.as("human").key_mv("knowledge.notes.alpha", "knowledge.notes.beta", dry_run: true)

      expect(result["dry_run"]).to be(true)
      expect(File.exist?(File.join(tmp, ".textus/data/knowledge/notes/alpha.md"))).to be(true)
      expect(File.exist?(File.join(tmp, ".textus/data/knowledge/notes/beta.md"))).to be(false)
    end
  end

  it "propagates correlation_id from ctx into the audit row" do
    Dir.mktmpdir do |tmp|
      Textus::Surface::CLI.run(["--root=#{tmp}/.textus", "init"], stdin: StringIO.new(""), stdout: StringIO.new, stderr: StringIO.new,
                                                                   cwd: tmp)
      store = Textus::Store.new(File.join(tmp, ".textus"))
      store.as("human").put("knowledge.notes.alpha", meta: { "name" => "alpha" }, body: "hi")

      store.as("human", correlation_id: "cid-test").key_mv("knowledge.notes.alpha", "knowledge.notes.beta")

      log_path = Textus::StoreGeometry.new(File.join(tmp, ".textus")).audit_log_path
      rows = File.readlines(log_path, chomp: true).map { |l| JSON.parse(l) }
      mv_row = rows.find { |r| r["verb"] == "key_mv" }
      expect(mv_row.dig("extras", "correlation_id")).to eq("cid-test")
    end
  end
end
