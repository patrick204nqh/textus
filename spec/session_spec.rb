require "spec_helper"
require "tmpdir"

RSpec.describe Textus::Session do
  def init_session(tmp, role: "human")
    Textus::CLI.run(["--root=#{tmp}/.textus", "init"], stdin: StringIO.new(""), stdout: StringIO.new, stderr: StringIO.new, cwd: tmp)
    store = Textus::Store.new(File.join(tmp, ".textus"))
    store.session(role: role)
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
      sess = init_session(tmp)
      surface_methods.each do |m|
        expect(sess).to respond_to(m), "expected Session##{m} to exist"
      end
    end
  end

  it "put returns an Envelope" do
    Dir.mktmpdir do |tmp|
      sess = init_session(tmp)
      env = sess.put("working.notes.alpha", body: "hello")
      expect(env).to be_a(Textus::Envelope)
    end
  end

  it "get returns an Envelope" do
    Dir.mktmpdir do |tmp|
      sess = init_session(tmp)
      sess.put("working.notes.alpha", body: "hello")
      env = sess.get("working.notes.alpha")
      expect(env).to be_a(Textus::Envelope)
    end
  end

  it "memoizes shared collaborators (envelope_reader/writer) across calls" do
    Dir.mktmpdir do |tmp|
      sess = init_session(tmp)
      # Touch session-built collaborators directly. Put no longer routes through
      # Session#envelope_writer post-0.27 collapse, but module-shaped use cases
      # still do — and we want to keep the memoization contract for those.
      r1 = sess.envelope_reader
      w1 = sess.envelope_writer
      r2 = sess.envelope_reader
      w2 = sess.envelope_writer
      expect(r1).to be_a(Textus::Application::Envelope::Reader)
      expect(w1).to be_a(Textus::Application::Envelope::Writer)
      expect(r1).to be(r2)
      expect(w1).to be(w2)
    end
  end

  it "can be constructed from explicit caps without going through .for(store)" do
    Dir.mktmpdir do |tmp|
      Textus::CLI.run(["--root=#{tmp}/.textus", "init"], stdin: StringIO.new(""), stdout: StringIO.new, stderr: StringIO.new, cwd: tmp)
      store = Textus::Store.new(File.join(tmp, ".textus"))
      read_caps, write_caps, hook_caps = Textus::Application.caps_from_store(store)
      sess = described_class.new(
        ctx: Textus::Application::Context.build(role: "human"),
        read_caps: read_caps,
        write_caps: write_caps,
        hook_caps: hook_caps,
      )
      env = sess.put("working.notes.alpha", body: "hi")
      expect(env).to be_a(Textus::Envelope)
      expect(sess.get("working.notes.alpha").body.strip).to eq("hi")
    end
  end

  it "with_role returns a new Session with the updated role" do
    Dir.mktmpdir do |tmp|
      sess = init_session(tmp)
      sess.put("working.notes.alpha", body: "x")

      other = sess.with_role("agent")
      expect(other).to be_a(Textus::Session)
      expect(other.ctx.role).to eq("agent")
      expect(sess.ctx.role).to eq("human")
      expect(other).not_to equal(sess)
    end
  end

  # Regression: deps / rdeps / published delegate correctly through Session
  context "dependency graph methods" do
    def projection_session(tmp)
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
      store.session
    end

    it "returns deps declared in projection.select" do
      Dir.mktmpdir do |tmp|
        sess = projection_session(tmp)
        expect(sess.deps("output.catalogs.people")).to eq(["working.people"])
      end
    end

    it "returns reverse dependencies" do
      Dir.mktmpdir do |tmp|
        sess = projection_session(tmp)
        expect(sess.rdeps("working.people")).to eq(["output.catalogs.people"])
      end
    end

    it "returns published entries with publish_to" do
      Dir.mktmpdir do |tmp|
        sess = projection_session(tmp)
        result = sess.published
        expect(result.map { |r| r["key"] }).to include("output.catalogs.people")
        rec = result.find { |r| r["key"] == "output.catalogs.people" }
        expect(rec["publish_to"]).to eq(["PEOPLE.md"])
      end
    end

    it "returns empty deps for an unknown key" do
      Dir.mktmpdir do |tmp|
        sess = projection_session(tmp)
        expect(sess.deps("does.not.exist")).to eq([])
      end
    end
  end
end
