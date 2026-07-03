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

  describe "Schema::Tools.migrate with authority role" do
    include_context "textus_store_fixture"

    it "uses the human role as migration author" do
      FileUtils.mkdir_p(File.join(root, "data/knowledge"))
      store = store_from_manifest(root, lanes: %w[knowledge], schemas: { note: NOTE_SCHEMA_BODY }, manifest: <<~YAML)
        version: textus/4
        data:
          knowledge:
            - key: knowledge.note
              schema: note
      YAML

      store.with_role("human").put(key: "knowledge.note",
                                   meta: { "name" => "note", "headline" => "My Headline" },
                                   body: "body text")

      res = Textus::Schema::Tools.migrate(store, name: "note", rename: nil)

      expect(res["migrated"]).to include("knowledge.note")

      env = store.with_role(Textus::Value::Role::DEFAULT).get(key: "knowledge.note")
      expect(env.meta).to have_key("title")
      expect(env.meta).not_to have_key("headline")

      audit = Textus::Protocol::Audit.new(root)
      expect(audit.last_writer_for("knowledge.note")).to eq("human")
    end

    it "uses knowledge lane's first writer as migration authority" do
      FileUtils.mkdir_p(File.join(root, "data/knowledge"))
      store = store_from_manifest(root, lanes: %w[knowledge], schemas: { note: NOTE_SCHEMA_BODY }, manifest: <<~YAML)
        version: textus/4
        data:
          knowledge:
            - key: knowledge.note
              schema: note
      YAML

      authority = Textus::Schema::Tools.accept_role_for(store)
      expect(authority).to eq("human")
    end
  end
end
