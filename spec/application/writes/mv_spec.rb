require "spec_helper"
require "tmpdir"
require "json"

RSpec.describe Textus::Application::Writes::Mv do
  it "moves an entry and publishes :entry_renamed via the bus" do
    Dir.mktmpdir do |tmp|
      Textus::CLI.run(["--root=#{tmp}/.textus", "init"], stdin: StringIO.new(""), stdout: StringIO.new, stderr: StringIO.new, cwd: tmp)
      store = Textus::Store.new(File.join(tmp, ".textus"))
      ops = Textus::Operations.for(store, role: "human")
      ops.put("working.notes.alpha", meta: { "name" => "alpha" }, body: "hello")

      events = []
      store.bus.subscribe(:entry_renamed, :mv_spec_capture) { |**kw| events << kw }

      ctx = Textus::Application::Context.legacy(store: store, role: "human")
      result = Textus::Application::Writes::Mv.new(ctx: ctx, envelope_io: build_envelope_io(ctx)).call("working.notes.alpha",
                                                                                                       "working.notes.beta")

      expect(result["ok"]).to be(true)
      expect(result["from_key"]).to eq("working.notes.alpha")
      expect(result["to_key"]).to eq("working.notes.beta")
      expect(events.size).to eq(1)
      expect(events.first[:from_key]).to eq("working.notes.alpha")
    end
  end

  it "supports dry_run without writing to disk" do
    Dir.mktmpdir do |tmp|
      Textus::CLI.run(["--root=#{tmp}/.textus", "init"], stdin: StringIO.new(""), stdout: StringIO.new, stderr: StringIO.new, cwd: tmp)
      store = Textus::Store.new(File.join(tmp, ".textus"))
      ops = Textus::Operations.for(store, role: "human")
      ops.put("working.notes.alpha", meta: { "name" => "alpha" }, body: "hello")

      ctx = Textus::Application::Context.legacy(store: store, role: "human")
      result = Textus::Application::Writes::Mv.new(ctx: ctx, envelope_io: build_envelope_io(ctx))
                                              .call("working.notes.alpha", "working.notes.beta", dry_run: true)

      expect(result["dry_run"]).to be(true)
      expect(File.exist?(File.join(tmp, ".textus/zones/working/notes/alpha.md"))).to be(true)
      expect(File.exist?(File.join(tmp, ".textus/zones/working/notes/beta.md"))).to be(false)
    end
  end

  it "propagates correlation_id from ctx into the audit row" do
    Dir.mktmpdir do |tmp|
      Textus::CLI.run(["--root=#{tmp}/.textus", "init"], stdin: StringIO.new(""), stdout: StringIO.new, stderr: StringIO.new, cwd: tmp)
      store = Textus::Store.new(File.join(tmp, ".textus"))
      Textus::Operations.for(store, role: "human").put("working.notes.alpha", meta: { "name" => "alpha" }, body: "hi")

      ctx = Textus::Application::Context.legacy(store: store, role: "human", correlation_id: "cid-test")
      Textus::Application::Writes::Mv.new(ctx: ctx, envelope_io: build_envelope_io(ctx)).call("working.notes.alpha", "working.notes.beta")

      log_path = File.join(tmp, ".textus/audit.log")
      rows = File.readlines(log_path, chomp: true).map { |l| JSON.parse(l) }
      mv_row = rows.find { |r| r["verb"] == "mv" }
      expect(mv_row.dig("extras", "correlation_id")).to eq("cid-test")
    end
  end
end
