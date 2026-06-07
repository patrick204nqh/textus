require "spec_helper"

NOTE_SCHEMA_BODY = YAML.dump({
                               "name" => "note",
                               "required" => [],
                               "optional" => %w[headline title],
                               "fields" => { "headline" => { "type" => "string" },
                                             "title" => { "type" => "string" } },
                               "evolution" => { "migrate_from" => { "headline" => "title" } },
                             })

RSpec.describe "Schema evolution" do
  describe "evolution metadata" do
    include_context "textus_store_fixture"

    before do
      FileUtils.mkdir_p(File.join(root, "schemas"))
      File.write(File.join(root, "schemas/person.yaml"), <<~YAML)
        name: person
        required: [full_name]
        fields:
          full_name:  { type: string, maintained_by: human }
          embedding:  { type: array,  maintained_by: ai }
          last_seen:  { type: time,   maintained_by: script }
        evolution:
          added_in: 2026-05-19
          migrate_from:
            name: full_name
      YAML
    end

    it "exposes maintained_by per field" do
      s = Textus::Schema.load(File.join(root, "schemas/person.yaml"))
      expect(s.maintained_by("full_name")).to eq("human")
      expect(s.maintained_by("embedding")).to eq("ai")
      expect(s.maintained_by("missing")).to be_nil
    end

    it "exposes evolution metadata" do
      s = Textus::Schema.load(File.join(root, "schemas/person.yaml"))
      expect(s.evolution["added_in"]).to eq("2026-05-19")
      expect(s.evolution["migrate_from"]).to eq({ "name" => "full_name" })
    end
  end

  describe "Schema::Tools.migrate with renamed authority role" do
    include_context "textus_store_fixture"

    let(:store_with_roles) do
      store_from_manifest(root, zones: %w[knowledge], schemas: { note: NOTE_SCHEMA_BODY }, manifest: <<~YAML)
        version: textus/3
        roles:
          - { name: human,  can: [author, propose] }
          - { name: agent,  can: [propose] }
        zones:
          - { name: knowledge, kind: canon }
        entries:
          - { key: knowledge.note, path: knowledge/note.md, zone: knowledge, schema: note, kind: leaf }
      YAML
    end

    it "migrate uses the declared author-capability role, not the literal human fallback" do
      store = store_with_roles

      store.as("human").put(
        "knowledge.note",
        meta: { "name" => "note", "headline" => "My Headline" },
        body: "body text",
      )

      res = Textus::Schema::Tools.migrate(store, name: "note", rename: nil)

      expect(res["migrated"]).to include("knowledge.note")

      env = store.as(Textus::Role::DEFAULT).get("knowledge.note")
      expect(env.meta).to have_key("title")
      expect(env.meta).not_to have_key("headline")

      audit = Textus::Ports::AuditLog.new(root)
      expect(audit.last_writer_for("knowledge.note")).to eq("human")
    end

    it "migrate raises UsageError when roles: is declared but no author kind exists" do
      store = store_from_manifest(root, zones: %w[knowledge], schemas: { note: NOTE_SCHEMA_BODY }, manifest: <<~YAML)
        version: textus/3
        roles:
          - { name: agent, can: [propose] }
        zones:
          - { name: proposals, kind: queue }
        entries:
          - { key: proposals.note, path: proposals/note.md, zone: proposals, schema: note, kind: leaf }
      YAML

      expect do
        Textus::Schema::Tools.migrate(store, name: "note", rename: nil)
      end.to raise_error(Textus::UsageError, /requires a role holding the 'author' capability/)
    end
  end

  # Conformance fixture C from textus/3 §12: schema validation.
  describe "Fixture C — schema validation" do
    include_context "textus/3 conformance fixture"

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
end
