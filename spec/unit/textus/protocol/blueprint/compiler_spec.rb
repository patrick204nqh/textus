RSpec.describe Textus::Protocol::Blueprint::Compiler do
  let(:schemas) { instance_double(Textus::Protocol::Schema::Registry) }

  let(:mentry) do
    Textus::Protocol::Manifest::Entry::Leaf.new(
      raw: {},
      key: "knowledge.loop.intent", path: "knowledge/loop/intent.md",
      lane: "knowledge", format: "markdown",
      naming: "sequential", schema: nil
    )
  end

  subject(:blueprint) { described_class.compile(mentry, schemas:) }

  it "returns a Blueprint" do
    expect(blueprint).to be_a(Textus::Protocol::Blueprint)
  end

  it "copies the key" do
    expect(blueprint.key).to eq("knowledge.loop.intent")
  end

  it "builds naming with pattern and example" do
    expect(blueprint.naming[:alias]).to eq("sequential")
    expect(blueprint.naming[:pattern]).to be_a(String)
    expect(blueprint.naming[:example]).to match(/\A\d{4}-/)
  end

  it "sets schema to nil when no schema ref" do
    expect(blueprint.schema).to be_nil
  end

  it "generates a meta_template" do
    expect(blueprint.meta_template).to be_a(String)
    expect(blueprint.meta_template).to include("---")
  end

  it "generates a template with valid naming" do
    expect(blueprint.template[:key]).to match(/\Aknowledge\.loop\.intent\.\d{4}-[a-z]/)
    expect(blueprint.template[:body]).to be_a(String)
  end

  context "with schema" do
    let(:mentry) do
      Textus::Protocol::Manifest::Entry::Leaf.new(
        raw: {},
        key: "knowledge.loop.execution.runbook", path: "knowledge/loop/execution/runbook.md",
        lane: "knowledge", format: "markdown",
        naming: "sequential", schema: "execution/runbook"
      )
    end
    let(:schema_obj) do
      instance_double(Textus::Protocol::Schema,
        name: "execution/runbook",
        required: %w[name description],
        optional: %w[steps],
        fields: {
          "name" => { "type" => "string", "description" => "Runbook name" },
          "description" => { "type" => "string", "description" => "Purpose" },
          "steps" => { "type" => "array", "items" => { "type" => "string" }, "description" => "Steps" }
        }
      )
    end

    before do
      allow(schemas).to receive(:fetch_or_nil).with("execution/runbook").and_return(schema_obj)
    end

    it "builds schema view with fields" do
      expect(blueprint.schema).not_to be_nil
      expect(blueprint.schema[:fields].map { |f| f[:name] }).to include("name", "description")
    end

    it "marks required fields" do
      name_field = blueprint.schema[:fields].find { |f| f[:name] == "name" }
      expect(name_field[:required]).to be true
    end

    it "generates meta_template from required fields" do
      expect(blueprint.meta_template).to include("name:")
      expect(blueprint.meta_template).to include("description:")
    end
  end
end
