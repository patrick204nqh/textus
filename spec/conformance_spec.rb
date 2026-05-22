require "fileutils"
require "tmpdir"
require "json"
require "stringio"
require "digest"

# Conformance fixtures A–D from textus/2 §12, plus CLI smoke tests.
RSpec.describe "textus/2 conformance" do
  let(:tmp)  { Dir.mktmpdir("textus-spec") }
  let(:root) { File.join(tmp, ".textus") }
  let(:store) { Textus::Store.new(root) }

  before do
    FileUtils.mkdir_p(File.join(root, "schemas"))
    FileUtils.mkdir_p(File.join(root, "zones/working/network/org"))
    FileUtils.mkdir_p(File.join(root, "zones/working/projects"))
    FileUtils.mkdir_p(File.join(root, "zones/output/catalogs"))
    FileUtils.mkdir_p(File.join(root, "zones/identity"))
    FileUtils.mkdir_p(File.join(root, "zones/inbox/calendar"))

    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/2
      zones:
        - { name: identity, writable_by: [human] }
        - { name: working,  writable_by: [human, ai, script] }
        - { name: output,   writable_by: [build] }
        - { name: inbox,    writable_by: [script] }
      entries:
        - { key: identity.self,         path: identity/self,         zone: identity, schema: null,   owner: human:patrick }
        - { key: working.network.org,   path: working/network/org,   zone: working,  schema: person, owner: human:patrick, nested: true }
        - { key: working.projects,      path: working/projects,      zone: working,  schema: null,   owner: human:patrick, nested: true }
        - { key: output.catalogs.skills, path: output/catalogs/skills, zone: output, schema: null, owner: build:catalog, generator: { command: "rake catalog:skills", sources: [working.projects] } }
        - key: inbox.calendar.events
          path: inbox/calendar/events
          zone: inbox
          schema: null
          owner: script:cron
          intake:
            handler: http_json
            config: { url: "https://example.com/calendar.ics" }
      policies:
        - match: inbox.calendar.events
          refresh:
            ttl: 1s
            on_stale: warn
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

      expect(env["protocol"]).to eq("textus/2")
      expect(env["key"]).to eq("working.network.org.jane")
      expect(env["zone"]).to eq("working")
      expect(env["owner"]).to eq("human:patrick")
      expect(File.absolute_path?(env["path"])).to be true
      expect(env["path"]).to end_with("working/network/org/jane.md")

      expect(env["_meta"]).to eq(
        "name" => "jane", "relationship" => "peer", "org" => "acme",
      )
      expect(env["body"]).to include("Short body in Markdown.")

      expected = "sha256:#{Digest::SHA256.hexdigest(File.binread(env["path"]))}"
      expect(env["etag"]).to eq(expected)
      expect(env["schema_ref"]).to eq("person")
    end
  end

  describe "Fixture B — role gate on write" do
    it "raises WriteForbidden when an AI tries to write identity" do
      expect do
        store.put("identity.self",
                  meta: { "name" => "self" }, body: "n/a", as: "ai")
      end.to raise_error(Textus::WriteForbidden) do |err|
        env = err.to_envelope
        expect(env["code"]).to eq("write_forbidden")
        expect(env["details"]["zone"]).to eq("identity")
      end
    end
  end

  describe "Fixture C — schema validation" do
    it "raises SchemaViolation listing the missing required field" do
      expect do
        store.put(
          "working.network.org.bob",
          meta: { "name" => "bob", "org" => "acme" },
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
    it "flags output entries with sources newer than generated.at without executing" do
      output_path = File.join(root, "zones/output/catalogs/skills.md")
      File.write(output_path, <<~MD)
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

      rows = store.stale(zone: "output")
      expect(rows.length).to eq(1)
      row = rows.first
      expect(row["key"]).to eq("output.catalogs.skills")
      expect(row["generator"]["command"]).to eq("rake catalog:skills")
      expect(row["reason"]).to match(/working\.projects/)
    end
  end

  describe "put --fetch=NAME" do
    it "parses stdin and writes entry with last_refreshed_at" do
      out = StringIO.new
      ics = "BEGIN:VEVENT\nSUMMARY:demo\nUID:1\nEND:VEVENT\n"
      rc = Textus::CLI.run(
        ["put", "inbox.calendar.events", "--fetch=ical-events",
         "--stdin", "--as=script", "--format=json"],
        stdin: StringIO.new(ics),
        stdout: out, stderr: StringIO.new, cwd: tmp
      )
      expect(rc).to eq(0)
      env = JSON.parse(out.string.lines.last)
      expect(env["_meta"]["last_refreshed_at"]).not_to be_nil
      expect(env["_meta"]["fetched_with"]).to eq("ical-events")
    end
  end

  describe "inbox staleness via TTL" do
    it "flags inbox entries that were never refreshed" do
      rows = store.stale(zone: "inbox")
      expect(rows.length).to eq(1)
      expect(rows.first["key"]).to eq("inbox.calendar.events")
      expect(rows.first["reason"]).to match(/never refreshed/)
    end

    it "flags inbox entries past their TTL" do
      inbox_path = File.join(root, "zones/inbox/calendar/events.md")
      stale_time = (Time.now - 10).utc.iso8601
      File.write(inbox_path, <<~MD)
        ---
        name: events
        last_refreshed_at: "#{stale_time}"
        ---
        body
      MD
      rows = store.stale(zone: "inbox")
      expect(rows.length).to eq(1)
      expect(rows.first["reason"]).to match(/ttl exceeded/i)
    end

    it "does not flag inbox entries within their TTL" do
      inbox_path = File.join(root, "zones/inbox/calendar/events.md")
      fresh_time = Time.now.utc.iso8601
      File.write(inbox_path, <<~MD)
        ---
        name: events
        last_refreshed_at: "#{fresh_time}"
        ---
        body
      MD
      rows = store.stale(zone: "inbox")
      expect(rows).to be_empty
    end
  end

  describe "zones block" do
    it "parses declared zones with writable_by" do
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/2
        zones:
          - { name: identity, writable_by: [human] }
          - { name: working,  writable_by: [human, ai, script] }
        entries:
          - { key: identity.self, path: identity/self.md, zone: identity, schema: null, owner: human:patrick }
      YAML
      FileUtils.mkdir_p(File.join(root, "zones/identity"))
      File.write(File.join(root, "zones/identity/self.md"), "---\nname: self\n---\n")
      m = Textus::Manifest.load(root)
      expect(m.zone_writers("identity")).to eq(["human"])
      expect(m.zone_writers("working")).to contain_exactly("human", "ai", "script")
    end

    it "raises BadFrontmatter if zones block is absent" do
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/2
        entries:
          - { key: state.x, path: state/x.md, zone: state, schema: null, owner: o }
      YAML
      expect { Textus::Manifest.load(root) }
        .to raise_error(Textus::BadFrontmatter, /manifest must declare zones/)
    end
  end

  describe "CLI" do
    it "emits a textus/2 envelope for `get`" do
      out = StringIO.new
      rc = Textus::CLI.run(
        ["get", "working.network.org.jane", "--format=json"],
        stdin: StringIO.new, stdout: out, stderr: StringIO.new, cwd: tmp,
      )
      expect(rc).to eq(0)
      env = JSON.parse(out.string.lines.last)
      expect(env["protocol"]).to eq("textus/2")
      expect(env["key"]).to eq("working.network.org.jane")
    end

    it "returns etag_mismatch when if_etag is stale" do
      out = StringIO.new
      rc = Textus::CLI.run(
        ["put", "working.network.org.jane", "--stdin", "--format=json"],
        stdin: StringIO.new(JSON.generate(
                              "_meta" => { "name" => "jane", "relationship" => "peer", "org" => "acme" },
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

  describe "CLI delete" do
    it "deletes via CLI with --as=human" do
      out = StringIO.new
      rc = Textus::CLI.run(
        ["delete", "working.network.org.jane", "--as=human", "--format=json"],
        stdin: StringIO.new, stdout: out, stderr: StringIO.new, cwd: tmp,
      )
      expect(rc).to eq(0)
      expect(JSON.parse(out.string.lines.last)["deleted"]).to be true
    end

    it "validate-all verb is removed in v0.5; doctor --check=schema_violations replaces it" do
      out = StringIO.new
      err = StringIO.new
      rc = Textus::CLI.run(["validate-all", "--format=json"],
                           stdin: StringIO.new, stdout: out, stderr: err, cwd: tmp)
      expect(rc).not_to eq(0)
      expect(JSON.parse(out.string.lines.last)["code"]).to eq("usage")
    end
  end

  describe "--zone filter on list" do
    it "returns only entries in the named zone" do
      expect(store.list(zone: "working").map { |r| r["zone"] }.uniq).to eq(["working"])
    end
  end

  describe "store#validate_all" do
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

  describe "CLI doctor schema_violations" do
    it "doctor --check=schema_violations returns ok in a clean tree" do
      out = StringIO.new
      rc = Textus::CLI.run(
        ["doctor", "--check=schema_violations", "--format=json"],
        stdin: StringIO.new, stdout: out, stderr: StringIO.new, cwd: tmp,
      )
      expect(rc).to eq(0)
      expect(JSON.parse(out.string.lines.last)["ok"]).to be true
    end
  end

  describe "delete verb" do
    it "deletes an entry, audit-logs it, and refuses without role" do
      store.put("working.network.org.tmp",
                meta: { "name" => "tmp", "relationship" => "peer", "org" => "acme" },
                body: "tmp", as: "human")
      res = store.delete("working.network.org.tmp", as: "human")
      expect(res["deleted"]).to be true
      expect(File.exist?(File.join(root, "zones/working/network/org/tmp.md"))).to be false
      expect(File.read(File.join(root, "audit.log"))).to match(/"verb":"delete"/)
    end

    it "rejects delete on identity by ai role" do
      File.write(File.join(root, "zones/identity/self.md"), "---\nname: self\n---\nx\n")
      expect { store.delete("identity.self", as: "ai") }
        .to raise_error(Textus::WriteForbidden)
    end
  end
end
