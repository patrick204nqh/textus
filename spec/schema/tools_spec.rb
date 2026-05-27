require "spec_helper"
require "fileutils"
require "tmpdir"
require "yaml"

RSpec.describe Textus::Schema::Tools do
  include_context "textus_store_fixture"

  before do
    FileUtils.mkdir_p(File.join(root, "zones/working/people"))
    FileUtils.mkdir_p(File.join(root, "schemas"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, write_policy: [human, agent, runner] }
      entries:
        - { key: working.people, path: working/people, zone: working, schema: null, owner: o, nested: true, kind: nested}

    YAML
  end

  def store = Textus::Store.new(root)

  it "schema-init infers a schema from an entry's frontmatter" do
    s = store
    Textus::Operations.for(s, role: "human").put(
      "working.people.alice",
      meta: { "name" => "alice", "org" => "acme", "age" => 30 },
      body: "",
    )

    res = Textus::Schema::Tools.init(s, name: "person", from: "working.people.alice")
    expect(res["schema_name"]).to eq("person")
    raw = YAML.safe_load_file(res["path"])
    expect(raw["required"]).to include("name", "org", "age")
    expect(raw["fields"]["age"]["type"]).to eq("number")
    expect(raw["fields"]["org"]["type"]).to eq("string")
  end

  it "schema-diff reports entries that violate the schema" do
    s = store
    Textus::Operations.for(s, role: "human").put(
      "working.people.alice",
      meta: { "name" => "alice", "org" => "acme" },
      body: "",
    )
    Textus::Operations.for(s, role: "human").put(
      "working.people.bob",
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
    expect(keys).to include("working.people.bob")
    expect(keys).not_to include("working.people.alice")
  end

  it "auto-applies migrate_from on schema-migrate without --rename" do
    s = store
    Textus::Operations.for(s, role: "human").put(
      "working.people.alice",
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
    env = Textus::Operations.for(store).get(res["migrated"].first)
    expect(env.meta).to have_key("full_name")
    expect(env.meta).not_to have_key("name")
  end

  it "schema-migrate renames a frontmatter field across entries that have it" do
    s = store
    Textus::Operations.for(s, role: "human").put(
      "working.people.alice",
      meta: { "name" => "alice", "org" => "acme" },
      body: "hello",
    )
    Textus::Operations.for(s, role: "human").put(
      "working.people.bob",
      meta: { "name" => "bob", "company" => "other" },
      body: "world",
    )

    res = Textus::Schema::Tools.migrate(store, name: "person", rename: "org:organization")
    expect(res["migrated"]).to eq(["working.people.alice"])

    env = Textus::Operations.for(store).get("working.people.alice")
    expect(env.meta["organization"]).to eq("acme")
    expect(env.meta).not_to have_key("org")
  end
end
