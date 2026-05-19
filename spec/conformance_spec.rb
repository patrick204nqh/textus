require "fileutils"
require "tmpdir"
require "json"
require "stringio"
require "digest"

# Conformance fixtures A–D from textus/1 §12, plus CLI smoke tests.
RSpec.describe "textus/1 conformance" do
  let(:tmp)  { Dir.mktmpdir("textus-spec") }
  let(:root) { File.join(tmp, ".textus") }
  let(:store) { Textus::Store.new(root) }

  before do
    FileUtils.mkdir_p(File.join(root, "schemas"))
    FileUtils.mkdir_p(File.join(root, "zones/working/network/org"))
    FileUtils.mkdir_p(File.join(root, "zones/working/projects"))
    FileUtils.mkdir_p(File.join(root, "zones/derived/catalogs"))
    FileUtils.mkdir_p(File.join(root, "zones/canon"))
    FileUtils.mkdir_p(File.join(root, "zones/intake/calendar"))

    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/1
      zones:
        - { name: canon,   writable_by: [human] }
        - { name: working, writable_by: [human, ai, script] }
        - { name: derived, writable_by: [build] }
        - { name: intake,  writable_by: [script] }
      entries:
        - { key: canon.identity,        path: canon/identity,        zone: canon,   schema: null,   owner: human:patrick }
        - { key: working.network.org,   path: working/network/org,   zone: working, schema: person, owner: human:patrick, nested: true }
        - { key: working.projects,      path: working/projects,      zone: working, schema: null,   owner: human:patrick, nested: true }
        - { key: derived.catalogs.skills, path: derived/catalogs/skills, zone: derived, schema: null, owner: build:catalog, generator: { command: "rake catalog:skills", sources: [working.projects] } }
        - key: intake.calendar.events
          path: intake/calendar/events
          zone: intake
          schema: null
          owner: script:cron
          source:
            fetcher: http_json
            config: { url: "https://example.com/calendar.ics" }
            ttl: 1s
    YAML

    File.write(File.join(root, "schemas/person.yaml"), <<~YAML)
      name: person
      required:
        - name
        - relationship
        - org
      optional:
        - notes
        - aliases
      fields:
        name:         { type: string, max: 80 }
        relationship: { type: enum, values: [peer, manager, report, external] }
        org:          { type: string }
        aliases:      { type: array, items: { type: string } }
        notes:        { type: string, max: 2000 }
    YAML

    File.write(File.join(root, "zones/working/network/org/jane.md"), <<~MD)
      ---
      name: jane
      relationship: peer
      org: acme
      ---
      Short body in Markdown.
    MD
  end

  after { FileUtils.remove_entry(tmp) if File.directory?(tmp) }

  describe "Fixture A — resolve and read" do
    it "returns the canonical envelope with a matching sha256 etag" do
      env = store.get("working.network.org.jane")

      expect(env["protocol"]).to eq("textus/1")
      expect(env["key"]).to eq("working.network.org.jane")
      expect(env["zone"]).to eq("working")
      expect(env["owner"]).to eq("human:patrick")
      expect(File.absolute_path?(env["path"])).to be true
      expect(env["path"]).to end_with("working/network/org/jane.md")

      expect(env["frontmatter"]).to eq(
        "name" => "jane", "relationship" => "peer", "org" => "acme",
      )
      expect(env["body"]).to include("Short body in Markdown.")

      expected = "sha256:#{Digest::SHA256.hexdigest(File.binread(env["path"]))}"
      expect(env["etag"]).to eq(expected)
      expect(env["schema_ref"]).to eq("person")
    end
  end

  describe "Fixture B — role gate on write" do
    it "raises WriteForbidden when an AI tries to write canon" do
      expect do
        store.put("canon.identity",
                  frontmatter: { "name" => "identity" }, body: "n/a", as: "ai")
      end.to raise_error(Textus::WriteForbidden) do |err|
        env = err.to_envelope
        expect(env["code"]).to eq("write_forbidden")
        expect(env["details"]["zone"]).to eq("canon")
      end
    end
  end

  describe "Fixture C — schema validation" do
    it "raises SchemaViolation listing the missing required field" do
      expect do
        store.put(
          "working.network.org.bob",
          frontmatter: { "name" => "bob", "org" => "acme" },
          body: "",
          as: "human",
        )
      end.to raise_error(Textus::SchemaViolation) do |err|
        env = err.to_envelope
        expect(env["code"]).to eq("schema_violation")
        expect(env["details"]["missing"]).to eq(["relationship"])
        expect(err.exit_code).to eq(1)
      end
    end
  end

  describe "Fixture D — staleness detection" do
    it "flags derived entries with sources newer than generated.at without executing" do
      derived_path = File.join(root, "zones/derived/catalogs/skills.md")
      File.write(derived_path, <<~MD)
        ---
        generated:
          by: "rake catalog:skills"
          at: "2020-01-01T00:00:00Z"
          from:
            - working.projects
        ---
        catalog body
      MD

      project_path = File.join(root, "zones/working/projects/acme.md")
      File.write(project_path, "---\nname: acme\n---\nproject body\n")
      File.utime(Time.now, Time.now, project_path)

      rows = store.stale(zone: "derived")
      expect(rows.length).to eq(1)
      row = rows.first
      expect(row["key"]).to eq("derived.catalogs.skills")
      expect(row["generator"]["command"]).to eq("rake catalog:skills")
      expect(row["reason"]).to match(/working\.projects/)
    end
  end

  describe "put --parse=NAME" do
    it "parses stdin and writes entry with last_refreshed_at" do
      out = StringIO.new
      ics = "BEGIN:VEVENT\nSUMMARY:demo\nUID:1\nEND:VEVENT\n"
      rc = Textus::CLI.run(
        ["put", "intake.calendar.events", "--parse=ical-events",
         "--stdin", "--as=script", "--format=json"],
        stdin: StringIO.new(ics),
        stdout: out, stderr: StringIO.new, cwd: tmp
      )
      expect(rc).to eq(0)
      env = JSON.parse(out.string.lines.last)
      expect(env["frontmatter"]["last_refreshed_at"]).not_to be_nil
      expect(env["frontmatter"]["parsed_with"]).to eq("ical-events")
    end
  end

  describe "intake staleness via TTL" do
    it "flags intake entries that were never refreshed" do
      rows = store.stale(zone: "intake")
      expect(rows.length).to eq(1)
      expect(rows.first["key"]).to eq("intake.calendar.events")
      expect(rows.first["reason"]).to match(/never refreshed/)
    end

    it "flags intake entries past their TTL" do
      intake_path = File.join(root, "zones/intake/calendar/events.md")
      stale_time = (Time.now - 10).utc.iso8601
      File.write(intake_path, <<~MD)
        ---
        name: events
        last_refreshed_at: "#{stale_time}"
        ---
        body
      MD
      rows = store.stale(zone: "intake")
      expect(rows.length).to eq(1)
      expect(rows.first["reason"]).to match(/ttl exceeded/i)
    end

    it "does not flag intake entries within their TTL" do
      intake_path = File.join(root, "zones/intake/calendar/events.md")
      fresh_time = Time.now.utc.iso8601
      File.write(intake_path, <<~MD)
        ---
        name: events
        last_refreshed_at: "#{fresh_time}"
        ---
        body
      MD
      rows = store.stale(zone: "intake")
      expect(rows).to be_empty
    end
  end

  describe "zones block" do
    it "parses declared zones with writable_by" do
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/1
        zones:
          - { name: canon,   writable_by: [human] }
          - { name: working, writable_by: [human, ai, script] }
        entries:
          - { key: canon.identity, path: canon/identity.md, zone: canon, schema: null, owner: human:patrick }
      YAML
      FileUtils.mkdir_p(File.join(root, "zones/canon"))
      File.write(File.join(root, "zones/canon/identity.md"), "---\nname: identity\n---\n")
      m = Textus::Manifest.load(root)
      expect(m.zone_writers("canon")).to eq(["human"])
      expect(m.zone_writers("working")).to contain_exactly("human", "ai", "script")
    end

    it "synthesizes default zones if zones block is absent (backward compat)" do
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/1
        entries:
          - { key: state.x, path: state/x.md, zone: state, schema: null, owner: o }
      YAML
      m = Textus::Manifest.load(root)
      expect(m.zone_writers("fixed")).to eq(["human"])
      expect(m.zone_writers("state")).to contain_exactly("human", "ai", "script")
      expect(m.zone_writers("derived")).to eq(["build"])
    end
  end

  describe "CLI" do
    it "emits a textus/1 envelope for `get`" do
      out = StringIO.new
      rc = Textus::CLI.run(
        ["get", "working.network.org.jane", "--format=json"],
        stdin: StringIO.new, stdout: out, stderr: StringIO.new, cwd: tmp,
      )
      expect(rc).to eq(0)
      env = JSON.parse(out.string.lines.last)
      expect(env["protocol"]).to eq("textus/1")
      expect(env["key"]).to eq("working.network.org.jane")
    end

    it "returns etag_mismatch when if_etag is stale" do
      out = StringIO.new
      rc = Textus::CLI.run(
        ["put", "working.network.org.jane", "--stdin", "--format=json"],
        stdin: StringIO.new(JSON.generate(
                              "frontmatter" => { "name" => "jane", "relationship" => "peer", "org" => "acme" },
                              "body" => "updated\n",
                              "if_etag" => "sha256:deadbeef",
                            )),
        stdout: out, stderr: StringIO.new, cwd: tmp
      )
      expect(rc).to eq(1)
      env = JSON.parse(out.string.lines.last)
      expect(env["code"]).to eq("etag_mismatch")
    end
  end

  describe "CLI delete + validate-all" do
    it "deletes via CLI with --as=human" do
      out = StringIO.new
      rc = Textus::CLI.run(
        ["delete", "working.network.org.jane", "--as=human", "--format=json"],
        stdin: StringIO.new, stdout: out, stderr: StringIO.new, cwd: tmp,
      )
      expect(rc).to eq(0)
      expect(JSON.parse(out.string.lines.last)["deleted"]).to be true
    end

    it "validate-all returns ok in a clean tree" do
      out = StringIO.new
      rc = Textus::CLI.run(
        ["validate-all", "--format=json"],
        stdin: StringIO.new, stdout: out, stderr: StringIO.new, cwd: tmp,
      )
      expect(rc).to eq(0)
      expect(JSON.parse(out.string.lines.last)["ok"]).to be true
    end
  end

  describe "--zone filter on list" do
    it "returns only entries in the named zone" do
      expect(store.list(zone: "working").map { |r| r["zone"] }.uniq).to eq(["working"])
    end
  end

  describe "validate-all" do
    it "returns ok when every entry conforms" do
      res = store.validate_all
      expect(res["ok"]).to be true
      expect(res["violations"]).to be_empty
    end

    it "reports schema violations and bad frontmatter" do
      File.write(File.join(root, "zones/working/network/org/broken.md"),
                 "---\nname: broken\n---\n")
      res = store.validate_all
      expect(res["ok"]).to be false
      keys = res["violations"].map { |v| v["key"] }
      expect(keys).to include("working.network.org.broken")
    end
  end

  describe "delete verb" do
    it "deletes an entry, audit-logs it, and refuses without role" do
      store.put("working.network.org.tmp",
                frontmatter: { "name" => "tmp", "relationship" => "peer", "org" => "acme" },
                body: "tmp", as: "human")
      res = store.delete("working.network.org.tmp", as: "human")
      expect(res["deleted"]).to be true
      expect(File.exist?(File.join(root, "zones/working/network/org/tmp.md"))).to be false
      expect(File.read(File.join(root, "audit.log"))).to match(/\tdelete\t/)
    end

    it "rejects delete on canon by ai role" do
      File.write(File.join(root, "zones/canon/identity.md"), "---\nname: identity\n---\nx\n")
      expect { store.delete("canon.identity", as: "ai") }
        .to raise_error(Textus::WriteForbidden)
    end
  end
end
