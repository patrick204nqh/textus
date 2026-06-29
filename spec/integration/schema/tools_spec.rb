require "spec_helper"

RSpec.describe Textus::Schema::Tools do
  include_context "textus_store_fixture"

  before do
    FileUtils.mkdir_p(File.join(root, "data/knowledge/people"))
    FileUtils.mkdir_p(File.join(root, "schemas"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/4
      lanes:
        - { name: knowledge, kind: canon }
      entries:
        - { key: knowledge.people, path: knowledge/people, lane: knowledge, owner: human:self, kind: nested}

    YAML
  end

  def store = Textus::Store.new(root)

  it "schema-init infers a schema from an entry's frontmatter" do
    s = store
    s.with_role("human").put(
      "knowledge.people.alice",
      meta: { "name" => "alice", "org" => "acme", "age" => 30 },
      body: "",
    )

    res = Textus::Schema::Tools.init(s, name: "person", from: "knowledge.people.alice")
    expect(res["schema_name"]).to eq("person")
    raw = YAML.safe_load_file(res["path"])
    expect(raw["required"]).to include("name", "org", "age")
    expect(raw["fields"]["age"]["type"]).to eq("number")
    expect(raw["fields"]["org"]["type"]).to eq("string")
  end

  it "schema-diff reports entries that violate the schema" do
    s = store
    s.with_role("human").put(
      "knowledge.people.alice",
      meta: { "name" => "alice", "org" => "acme" },
      body: "",
    )
    s.with_role("human").put(
      "knowledge.people.bob",
      meta: { "name" => "bob" },
      body: "",
    )

    File.write(File.join(root, "schemas", "person.yaml"), YAML.dump({
                                                                      "name" => "person",
                                                                      "required" => %w[name org],
                                                                      "optional" => [],
                                                                      "fields" => { "name" => { "type" => "string" },
                                                                                    "org" => { "type" => "string" } },
                                                                    }))

    res = Textus::Schema::Tools.diff(store, name: "person")
    keys = res["drift"].map { |d| d["key"] }
    expect(keys).to include("knowledge.people.bob")
    expect(keys).not_to include("knowledge.people.alice")
  end

  it "auto-applies migrate_from on schema-migrate without --rename" do
    s = store
    s.with_role("human").put(
      "knowledge.people.alice",
      meta: { "name" => "alice" },
      body: "hello",
    )

    File.write(File.join(root, "schemas", "person.yaml"), YAML.dump({
                                                                      "name" => "person",
                                                                      "required" => ["full_name"],
                                                                      "fields" => { "full_name" => { "type" => "string" } },
                                                                      "evolution" => { "migrate_from" => { "name" => "full_name" } },
                                                                    }))

    res = Textus::Schema::Tools.migrate(store, name: "person", rename: nil)
    expect(res["migrated"]).not_to be_empty
    env = store.with_role(Textus::Value::Role::DEFAULT).get(res["migrated"].first)
    expect(env.meta).to have_key("full_name")
    expect(env.meta).not_to have_key("name")
  end

  it "schema-migrate renames a frontmatter field across entries that have it" do
    s = store
    s.with_role("human").put(
      "knowledge.people.alice",
      meta: { "name" => "alice", "org" => "acme" },
      body: "hello",
    )
    s.with_role("human").put(
      "knowledge.people.bob",
      meta: { "name" => "bob", "company" => "other" },
      body: "world",
    )

    res = Textus::Schema::Tools.migrate(store, name: "person", rename: "org:organization")
    expect(res["migrated"]).to eq(["knowledge.people.alice"])

    env = store.with_role(Textus::Value::Role::DEFAULT).get("knowledge.people.alice")
    expect(env.meta["organization"]).to eq("acme")
    expect(env.meta).not_to have_key("org")
  end
end
