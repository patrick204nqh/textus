require "spec_helper"
require "tmpdir"

RSpec.describe Textus::Operations do
  def init_ops(tmp, role: "human")
    Textus::CLI.run(["--root=#{tmp}/.textus", "init"], stdin: StringIO.new(""), stdout: StringIO.new, stderr: StringIO.new, cwd: tmp)
    store = Textus::Store.new(File.join(tmp, ".textus"))
    Textus::Operations.for(store, role: role)
  end

  it "responds to the entire flat surface" do
    surface_methods = %i[
      put delete mv accept reject publish
      get get_or_refresh list where uid schema_envelope
      deps rdeps published stale audit blame policy_explain
      freshness validate_all
      refresh refresh_all
    ]
    Dir.mktmpdir do |tmp|
      ops = init_ops(tmp)
      surface_methods.each do |m|
        expect(ops).to respond_to(m), "expected Operations#{m} to exist"
      end
    end
  end

  it "put returns an Envelope" do
    Dir.mktmpdir do |tmp|
      ops = init_ops(tmp)
      env = ops.put("working.notes.alpha", body: "hello")
      expect(env).to be_a(Textus::Envelope)
    end
  end

  it "get returns an Envelope" do
    Dir.mktmpdir do |tmp|
      ops = init_ops(tmp)
      ops.put("working.notes.alpha", body: "hello")
      env = ops.get("working.notes.alpha")
      expect(env).to be_a(Textus::Envelope)
    end
  end

  it "memoizes shared collaborators (envelope_reader/writer, orchestrator) across calls" do
    Dir.mktmpdir do |tmp|
      ops = init_ops(tmp)
      ops.put("working.notes.alpha", body: "one")
      ops.put("working.notes.alpha", body: "two")
      reader = ops.instance_variable_get(:@envelope_reader)
      writer = ops.instance_variable_get(:@envelope_writer)
      expect(reader).to be_a(Textus::Application::Envelope::Reader)
      expect(writer).to be_a(Textus::Application::Envelope::Writer)
    end
  end

  it "does not memoize per-op use cases (constructs fresh on each call)" do
    Dir.mktmpdir do |tmp|
      ops = init_ops(tmp)
      ops.put("working.notes.alpha", body: "hello")
      expect(ops.instance_variable_get(:@put_op)).to be_nil
      expect(ops.instance_variable_get(:@get_op)).to be_nil
    end
  end

  it "can be constructed from explicit caps without going through .for(store)" do
    Dir.mktmpdir do |tmp|
      Textus::CLI.run(["--root=#{tmp}/.textus", "init"], stdin: StringIO.new(""), stdout: StringIO.new, stderr: StringIO.new, cwd: tmp)
      store = Textus::Store.new(File.join(tmp, ".textus"))
      read_caps, write_caps, hook_caps = Textus::Application.caps_from_store(store)
      ops = described_class.new(
        ctx: Textus::Application::Context.build(role: "human"),
        read_caps: read_caps,
        write_caps: write_caps,
        hook_caps: hook_caps,
      )
      env = ops.put("working.notes.alpha", body: "hi")
      expect(env).to be_a(Textus::Envelope)
      expect(ops.get("working.notes.alpha").body.strip).to eq("hi")
    end
  end

  it "with_role returns a new Operations with fresh memoization" do
    Dir.mktmpdir do |tmp|
      ops = init_ops(tmp)
      ops.put("working.notes.alpha", body: "x")
      original_put_op = ops.instance_variable_get(:@put_op)

      other = ops.with_role("agent")
      expect(other).to be_a(Textus::Operations)
      expect(other.ctx.role).to eq("agent")
      expect(ops.ctx.role).to eq("human")
      expect(other.instance_variable_get(:@put_op)).to be_nil
      expect(other).not_to equal(ops)
      expect(original_put_op).to equal(ops.instance_variable_get(:@put_op))
    end
  end

  # Regression: deps / rdeps / published delegate correctly through Operations
  context "dependency graph methods" do
    def projection_ops(tmp)
      root = File.join(tmp, ".textus")
      FileUtils.mkdir_p(File.join(root, "zones/working/people"))
      FileUtils.mkdir_p(File.join(root, "zones/output"))
      FileUtils.mkdir_p(File.join(root, "templates"))

      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/3
        zones:
          - { name: working, write_policy: [human, agent, runner] }
          - { name: output, write_policy: [builder] }
        entries:
          - { key: working.people, path: working/people, zone: working, schema: null, owner: o, nested: true, kind: nested}

          - key: output.catalogs.people
            kind: derived
            path: output/catalogs/people.md
            zone: output
            schema: null
            owner: builder:auto
            compute: { kind: projection, select: working.people, pluck: [name, org], sort_by: name }
            template: people.mustache
            publish_to: [PEOPLE.md]
      YAML

      store = Textus::Store.new(root)
      Textus::Operations.for(store)
    end

    it "returns deps declared in projection.select" do
      Dir.mktmpdir do |tmp|
        ops = projection_ops(tmp)
        expect(ops.deps("output.catalogs.people")).to eq(["working.people"])
      end
    end

    it "returns reverse dependencies" do
      Dir.mktmpdir do |tmp|
        ops = projection_ops(tmp)
        expect(ops.rdeps("working.people")).to eq(["output.catalogs.people"])
      end
    end

    it "returns published entries with publish_to" do
      Dir.mktmpdir do |tmp|
        ops = projection_ops(tmp)
        result = ops.published
        expect(result.map { |r| r["key"] }).to include("output.catalogs.people")
        rec = result.find { |r| r["key"] == "output.catalogs.people" }
        expect(rec["publish_to"]).to eq(["PEOPLE.md"])
      end
    end

    it "returns empty deps for an unknown key" do
      Dir.mktmpdir do |tmp|
        ops = projection_ops(tmp)
        expect(ops.deps("does.not.exist")).to eq([])
      end
    end
  end
end
