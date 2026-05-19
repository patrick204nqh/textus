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
    FileUtils.mkdir_p(File.join(root, "zones/state/network/org"))
    FileUtils.mkdir_p(File.join(root, "zones/state/projects"))
    FileUtils.mkdir_p(File.join(root, "zones/derived/catalogs"))
    FileUtils.mkdir_p(File.join(root, "zones/fixed"))

    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/1
      entries:
        - key: fixed.identity
          path: fixed/identity
          zone: fixed
          schema: null
          owner: textus:identity

        - key: state.network.org
          path: state/network/org
          zone: state
          schema: person
          owner: textus:network
          nested: true

        - key: state.projects
          path: state/projects
          zone: state
          schema: null
          owner: textus:projects
          nested: true

        - key: derived.catalogs.skills
          path: derived/catalogs/skills
          zone: derived
          schema: null
          owner: textus:build
          generator:
            command: "rake catalog:skills"
            sources:
              - state.projects
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

    File.write(File.join(root, "zones/state/network/org/jane.md"), <<~MD)
      ---
      name: jane
      relationship: peer
      org: envato
      ---
      Short body in Markdown.
    MD
  end

  after { FileUtils.remove_entry(tmp) if File.directory?(tmp) }

  describe "Fixture A — resolve and read" do
    it "returns the canonical envelope with a matching sha256 etag" do
      env = store.get("state.network.org.jane")

      expect(env["protocol"]).to eq("textus/1")
      expect(env["key"]).to eq("state.network.org.jane")
      expect(env["zone"]).to eq("state")
      expect(env["owner"]).to eq("textus:network")
      expect(File.absolute_path?(env["path"])).to be true
      expect(env["path"]).to end_with("state/network/org/jane.md")

      expect(env["frontmatter"]).to eq(
        "name" => "jane", "relationship" => "peer", "org" => "envato",
      )
      expect(env["body"]).to include("Short body in Markdown.")

      expected = "sha256:#{Digest::SHA256.hexdigest(File.binread(env["path"]))}"
      expect(env["etag"]).to eq(expected)
      expect(env["schema_ref"]).to eq("person")
    end
  end

  describe "Fixture B — zone gate on write" do
    it "raises WriteForbidden with code 'write_forbidden' and exit 1" do
      expect {
        store.put("fixed.identity", frontmatter: { "name" => "identity" }, body: "n/a")
      }.to raise_error(Textus::WriteForbidden) do |err|
        env = err.to_envelope
        expect(env["ok"]).to eq(false)
        expect(env["code"]).to eq("write_forbidden")
        expect(env["details"]["zone"]).to eq("fixed")
        expect(err.exit_code).to eq(1)
      end
    end
  end

  describe "Fixture C — schema validation" do
    it "raises SchemaViolation listing the missing required field" do
      expect {
        store.put(
          "state.network.org.bob",
          frontmatter: { "name" => "bob", "org" => "envato" },
          body: "",
        )
      }.to raise_error(Textus::SchemaViolation) do |err|
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
            - state.projects
        ---
        catalog body
      MD

      project_path = File.join(root, "zones/state/projects/acme.md")
      File.write(project_path, "---\nname: acme\n---\nproject body\n")
      File.utime(Time.now, Time.now, project_path)

      rows = store.stale
      expect(rows.length).to eq(1)
      row = rows.first
      expect(row["key"]).to eq("derived.catalogs.skills")
      expect(row["generator"]["command"]).to eq("rake catalog:skills")
      expect(row["reason"]).to match(/state\.projects/)
    end
  end

  describe "CLI" do
    it "emits a textus/1 envelope for `get`" do
      out = StringIO.new
      rc = Textus::CLI.run(
        ["get", "state.network.org.jane", "--format=json"],
        stdin: StringIO.new, stdout: out, stderr: StringIO.new, cwd: tmp,
      )
      expect(rc).to eq(0)
      env = JSON.parse(out.string.lines.last)
      expect(env["protocol"]).to eq("textus/1")
      expect(env["key"]).to eq("state.network.org.jane")
    end

    it "returns etag_mismatch when if_etag is stale" do
      out = StringIO.new
      rc = Textus::CLI.run(
        ["put", "state.network.org.jane", "--stdin", "--format=json"],
        stdin: StringIO.new(JSON.generate(
          "frontmatter" => { "name" => "jane", "relationship" => "peer", "org" => "envato" },
          "body" => "updated\n",
          "if_etag" => "sha256:deadbeef",
        )),
        stdout: out, stderr: StringIO.new, cwd: tmp,
      )
      expect(rc).to eq(1)
      env = JSON.parse(out.string.lines.last)
      expect(env["code"]).to eq("etag_mismatch")
    end
  end
end
