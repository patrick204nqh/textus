require "spec_helper"

# Proves the dogfood schema_registry_handler hook (ADR 0097): the handler is
# loaded through the real Loader so it exercises the same code path as the
# live `.textus/hooks/` directory, and invoked through the RpcRegistry — the
# same surface every intake handler goes through at runtime.
RSpec.describe "schema_registry_handler" do
  let(:events)  { Textus::Hooks::EventBus.new }
  let(:rpc)     { Textus::Hooks::RpcRegistry.new }

  # Build a real Schemas instance from the dogfood store so the test exercises
  # genuine Schema objects (name/required/optional/fields) rather than mocks.
  let(:schemas_dir) { File.expand_path("../../../.textus/schemas", __dir__) }
  let(:schemas)     { Textus::Schemas.new(schemas_dir) }

  # caps must expose both .rpc (for RpcRegistry dispatch) and .schemas (used
  # by this handler). Build with a minimal Struct so no Container is needed.
  let(:caps) { Struct.new(:rpc, :schemas).new(rpc, schemas) }

  before do
    # Load just the one hook file in isolation by copying it into a tmpdir so
    # other .textus/hooks/*.rb files do not register into this fresh registry.
    handler_path = File.expand_path("../../../.textus/hooks/schema_registry_handler.rb", __dir__)
    Dir.mktmpdir do |dir|
      FileUtils.cp(handler_path, File.join(dir, "schema_registry_handler.rb"))
      Textus::Hooks::Loader.new(events: events, rpc: rpc).load_dir(dir)
    end
  end

  it "registers a :schema resolve_handler" do
    expect(rpc.names(:resolve_handler)).to include(:schema)
  end

  it "emits schemas sorted by name, each with a fields list" do
    result = rpc.invoke(:resolve_handler, :schema, caps: caps, config: {}, args: [])
    schema_rows = result["content"]["schemas"]

    expect(schema_rows).to be_an(Array)
    names = schema_rows.map { |s| s["name"] }
    expect(names).to eq(names.sort)
    expect(schema_rows.first.keys).to include("name", "fields")
  end

  it "normalizes per-field required: true into a per-field required boolean" do
    # The dogfood schemas carry no top-level required: list — required-ness is
    # a per-field flag. The doc would be blank if we only read the top-level
    # list, so this guards that we surface the per-field truth.
    result = rpc.invoke(:resolve_handler, :schema, caps: caps, config: {}, args: [])
    project = result["content"]["schemas"].find { |s| s["name"] == "project" }
    name_field = project["fields"].find { |f| f["name"] == "name" }
    repo_field = project["fields"].find { |f| f["name"] == "repo" }

    expect(name_field["required"]).to be(true)         # name: { required: true }
    expect(repo_field["required"]).to be(false)        # repo: no required flag
    expect(name_field["type"]).to eq("string")
    expect(name_field["maintained_by"]).to eq("human")
  end

  it "includes the dogfood 'project' schema" do
    result = rpc.invoke(:resolve_handler, :schema, caps: caps, config: {}, args: [])
    names = result["content"]["schemas"].map { |s| s["name"] }
    expect(names).to include("project")
  end

  it "includes the dogfood 'runbook' schema" do
    result = rpc.invoke(:resolve_handler, :schema, caps: caps, config: {}, args: [])
    names = result["content"]["schemas"].map { |s| s["name"] }
    expect(names).to include("runbook")
  end

  it "emits fields sorted by name, each with name/type/required/maintained_by" do
    result = rpc.invoke(:resolve_handler, :schema, caps: caps, config: {}, args: [])
    result["content"]["schemas"].each do |row|
      field_names = row["fields"].map { |f| f["name"] }
      expect(field_names).to eq(field_names.sort)
      row["fields"].each do |f|
        expect(f.keys).to include("name", "type", "required", "maintained_by")
        expect(f["required"]).to be(true).or be(false)
      end
    end
  end

  it "has deterministic output (sorted by name)" do
    r1 = rpc.invoke(:resolve_handler, :schema, caps: caps, config: {}, args: [])
    r2 = rpc.invoke(:resolve_handler, :schema, caps: caps, config: {}, args: [])
    expect(r1["content"]["schemas"].map { |s| s["name"] })
      .to eq(r2["content"]["schemas"].map { |s| s["name"] })
  end
end
