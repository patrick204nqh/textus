require "stringio"
require "digest"

# Conformance fixtures A–D from textus/3 §12, plus CLI smoke tests.
RSpec.describe "textus/3 conformance" do
  let(:tmp)  { Dir.mktmpdir("textus-spec") }
  let(:root) { File.join(tmp, ".textus") }
  let(:store) { Textus::Store.new(root) }

  before do
    FileUtils.mkdir_p(File.join(root, "schemas"))
    FileUtils.mkdir_p(File.join(root, "zones/knowledge/network/org"))
    FileUtils.mkdir_p(File.join(root, "zones/knowledge/projects"))
    FileUtils.mkdir_p(File.join(root, "zones/artifacts/catalogs"))
    FileUtils.mkdir_p(File.join(root, "zones/identity"))
    FileUtils.mkdir_p(File.join(root, "zones/feeds/calendar"))

    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: identity,  kind: canon }
        - { name: knowledge,   kind: canon }
        - { name: artifacts, kind: derived }
        - { name: feeds,     kind: quarantine }
      entries:
        - { key: identity.self,         path: identity/self,         zone: identity,   owner: human:patrick, kind: leaf}

        - { key: knowledge.network.org,   path: knowledge/network/org,   zone: knowledge,  schema: person, owner: human:patrick, kind: nested}

        - { key: knowledge.projects,      path: knowledge/projects,      zone: knowledge,    owner: human:patrick, kind: nested}

        - { key: artifacts.catalogs.skills, path: artifacts/catalogs/skills, zone: artifacts, owner: automation:catalog, kind: derived, compute: { kind: external, command: "rake catalog:skills", sources: [knowledge.projects] } }
        - key: feeds.calendar.events
          kind: intake
          path: feeds/calendar/events
          zone: feeds
          owner: automation:cron
          intake:
            handler: http_json
            config: { url: "https://example.com/calendar.ics" }
      rules:
        - match: feeds.calendar.events
          upkeep:
            "on": stale
            ttl: 300s
            action: warn
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

    File.write(File.join(root, "zones/knowledge/network/org/jane.md"), <<~MD)
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
      env = store.as(Textus::Role::DEFAULT).get("knowledge.network.org.jane")

      aggregate_failures do
        expect(env.protocol).to eq("textus/3")
        expect(env.key).to eq("knowledge.network.org.jane")
        expect(env.zone).to eq("knowledge")
        expect(env.owner).to eq("human:patrick")
        expect(File.absolute_path?(env.path)).to be true
        expect(env.path).to end_with("knowledge/network/org/jane.md")

        expect(env.meta).to eq(
          "name" => "jane", "relationship" => "peer", "org" => "acme",
        )
        expect(env.body).to include("Short body in Markdown.")

        expected = "sha256:#{Digest::SHA256.hexdigest(File.binread(env.path))}"
        expect(env.etag).to eq(expected)
        expect(env.schema_ref).to eq("person")
      end
    end
  end

  describe "Fixture B — role gate on write" do
    it "raises WriteForbidden when an agent tries to write identity" do
      expect do
        store.as("agent").put("identity.self",
                              meta: { "name" => "self" }, body: "n/a")
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
        store.as("human").put(
          "knowledge.network.org.bob",
          meta: { "name" => "bob", "org" => "acme" },
          body: "",
        )
      end.to raise_error(Textus::SchemaViolation) do |err|
        env = err.to_envelope
        expect(env["code"]).to eq("schema_violation")
        expect(env["details"]["missing"]).to eq(["relationship"])
        expect(err.exit_code).to eq(1)
      end
    end
  end

  describe "Fixture D — generator drift detection (via doctor)" do
    it "flags artifacts entries with sources newer than generated.at without executing" do
      artifacts_path = File.join(root, "zones/artifacts/catalogs/skills.md")
      File.write(artifacts_path, <<~MD)
        ---
        generated:
          by: "rake catalog:skills"
          at: "2020-01-01T00:00:00Z"
          from:
            - knowledge.projects
        ---
        catalog body
      MD

      project_path = File.join(root, "zones/knowledge/projects/acme.md")
      File.write(project_path, "---\nname: acme\n---\nproject body\n")
      File.utime(Time.now, Time.now, project_path)

      drift = store.as(Textus::Role::DEFAULT).doctor["issues"]
                   .select { |i| i["code"] == "generator_drift" }
      expect(drift.length).to eq(1)
      row = drift.first
      expect(row["subject"]).to eq("artifacts.catalogs.skills")
      expect(row["message"]).to match(/knowledge\.projects/)
    end
  end

  describe "feeds lifecycle via TTL (freshness)" do
    def feeds_row
      store.as(Textus::Role::DEFAULT).freshness(zone: "feeds")
           .find { |r| r[:key] == "feeds.calendar.events" }
    end

    it "marks a never-recorded feeds entry expired" do
      row = feeds_row
      expect(row[:status]).to eq(:expired)
      expect(row[:reason]).to match(/never recorded/)
    end

    it "marks a feeds entry past its TTL expired" do
      feeds_path = File.join(root, "zones/feeds/calendar/events.md")
      # Well past the 300s TTL. Wide margin keeps this deterministic regardless of
      # iso8601 second-truncation in last_fetched_at.
      stale_time = (Time.now - 3600).utc.iso8601
      File.write(feeds_path, <<~MD)
        ---
        name: events
        last_fetched_at: "#{stale_time}"
        ---
        body
      MD
      row = feeds_row
      expect(row[:status]).to eq(:expired)
      expect(row[:reason]).to match(/ttl exceeded/i)
    end

    it "marks a feeds entry within its TTL fresh" do
      feeds_path = File.join(root, "zones/feeds/calendar/events.md")
      fresh_time = Time.now.utc.iso8601
      File.write(feeds_path, <<~MD)
        ---
        name: events
        last_fetched_at: "#{fresh_time}"
        ---
        body
      MD
      expect(feeds_row[:status]).to eq(:fresh)
    end
  end

  describe "zones block" do
    it "derives zone writers from capability × zone-kind" do
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/3
        zones:
          - { name: identity, kind: canon }
          - { name: proposals,  kind: queue }
        entries:
          - { key: identity.self, path: identity/self.md, zone: identity, owner: human:patrick, kind: leaf}

      YAML
      FileUtils.mkdir_p(File.join(root, "zones/identity"))
      File.write(File.join(root, "zones/identity/self.md"), "---\nname: self\n---\n")
      m = Textus::Manifest.load(root)
      # canon requires author; only human holds it under the default mapping.
      expect(m.policy.zone_writers("identity")).to eq(["human"])
      # queue requires propose; both human and agent hold it.
      expect(m.policy.zone_writers("proposals")).to contain_exactly("human", "agent")
    end

    it "raises BadFrontmatter if zones block is absent" do
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/3
        entries:
          - { key: state.x, path: state/x.md, zone: state, owner: human:self, kind: leaf}

      YAML
      expect { Textus::Manifest.load(root) }
        .to raise_error(Textus::BadFrontmatter, /manifest must declare zones/)
    end
  end

  describe "CLI" do
    it "emits a textus/3 envelope for `get`" do
      out = StringIO.new
      rc = Textus::CLI.run(
        ["get", "knowledge.network.org.jane", "--output=json"],
        stdin: StringIO.new, stdout: out, stderr: StringIO.new, cwd: tmp,
      )
      expect(rc).to eq(0)
      env = JSON.parse(out.string.lines.last)
      expect(env["protocol"]).to eq("textus/3")
      expect(env["key"]).to eq("knowledge.network.org.jane")
    end

    it "returns etag_mismatch when if_etag is stale" do
      out = StringIO.new
      rc = Textus::CLI.run(
        ["put", "knowledge.network.org.jane", "--stdin", "--output=json"],
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
        ["key", "delete", "knowledge.network.org.jane", "--as=human", "--output=json"],
        stdin: StringIO.new, stdout: out, stderr: StringIO.new, cwd: tmp,
      )
      expect(rc).to eq(0)
      expect(JSON.parse(out.string.lines.last)["deleted"]).to be true
    end

    it "validate-all verb is removed in v0.5; doctor --check=schema_violations replaces it" do
      out = StringIO.new
      err = StringIO.new
      rc = Textus::CLI.run(["validate-all", "--output=json"],
                           stdin: StringIO.new, stdout: out, stderr: err, cwd: tmp)
      expect(rc).not_to eq(0)
      expect(JSON.parse(out.string.lines.last)["code"]).to eq("usage")
    end
  end

  describe "--zone filter on list" do
    it "returns only entries in the named zone" do
      expect(store.as(Textus::Role::DEFAULT).list(zone: "knowledge").map { |r| r["zone"] }.uniq).to eq(["knowledge"])
    end
  end

  describe "store#validate_all" do
    it "returns ok when every entry conforms" do
      res = store.as(Textus::Role::DEFAULT).validate_all
      expect(res["ok"]).to be true
      expect(res["violations"]).to be_empty
    end

    it "reports schema violations and bad frontmatter" do
      File.write(File.join(root, "zones/knowledge/network/org/broken.md"),
                 "---\nname: broken\n---\n")
      res = store.as(Textus::Role::DEFAULT).validate_all
      expect(res["ok"]).to be false
      keys = res["violations"].map { |v| v["key"] }
      expect(keys).to include("knowledge.network.org.broken")
    end
  end
end
