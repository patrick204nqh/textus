# rubocop:disable RSpec/MultipleDescribes
require "spec_helper"
require "fileutils"
require "tmpdir"
require "json"

RSpec.describe "Schema evolution metadata" do
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

RSpec.describe "Schema::Tools.migrate with renamed authority role" do
  include_context "textus_store_fixture"

  def build_store_with_roles
    FileUtils.mkdir_p(File.join(root, "zones/working"))
    FileUtils.mkdir_p(File.join(root, "schemas"))

    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      roles:
        - { name: owner,  kind: accept_authority }
        - { name: agent,  kind: proposer }
      zones:
        - { name: working, write_policy: [owner, agent] }
      entries:
        - { key: working.note, path: working/note.md, zone: working, schema: note, kind: leaf }
    YAML

    File.write(File.join(root, "schemas/note.yaml"), YAML.dump({
                                                                 "name" => "note",
                                                                 "required" => [],
                                                                 "optional" => %w[headline title],
                                                                 "fields" => { "headline" => { "type" => "string" },
                                                                               "title" => { "type" => "string" } },
                                                                 "evolution" => { "migrate_from" => { "headline" => "title" } },
                                                               }))

    Textus::Store.new(root)
  end

  it "migrate uses the declared accept_authority role (owner), not the literal human fallback" do
    store = build_store_with_roles

    store.as("owner").put(
      "working.note",
      meta: { "name" => "note", "headline" => "My Headline" },
      body: "body text",
    )

    res = Textus::Schema::Tools.migrate(store, name: "note", rename: nil)

    expect(res["migrated"]).to include("working.note")

    env = store.as(Textus::Role::DEFAULT).get("working.note")
    expect(env.meta).to have_key("title")
    expect(env.meta).not_to have_key("headline")

    audit = Textus::Ports::AuditLog.new(root)
    expect(audit.last_writer_for("working.note")).to eq("owner")
  end

  it "migrate raises UsageError when roles: is declared but no accept_authority kind exists" do
    FileUtils.mkdir_p(File.join(root, "zones/working"))
    FileUtils.mkdir_p(File.join(root, "schemas"))

    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      roles:
        - { name: agent, kind: proposer }
      zones:
        - { name: working, write_policy: [agent] }
      entries:
        - { key: working.note, path: working/note.md, zone: working, schema: note, kind: leaf }
    YAML

    File.write(File.join(root, "schemas/note.yaml"), YAML.dump({
                                                                 "name" => "note",
                                                                 "required" => [],
                                                                 "optional" => %w[headline title],
                                                                 "fields" => { "headline" => { "type" => "string" },
                                                                               "title" => { "type" => "string" } },
                                                                 "evolution" => { "migrate_from" => { "headline" => "title" } },
                                                               }))

    store = Textus::Store.new(root)

    expect do
      Textus::Schema::Tools.migrate(store, name: "note", rename: nil)
    end.to raise_error(Textus::UsageError, /no role with accept_authority kind|requires a role with kind :accept_authority/)
  end
end
# rubocop:enable RSpec/MultipleDescribes
