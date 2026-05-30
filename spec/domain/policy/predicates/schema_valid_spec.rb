require "spec_helper"

RSpec.describe Textus::Domain::Policy::Predicates::SchemaValid do
  let(:schema)     { instance_double(Textus::Schema) }
  let(:schemas)    { instance_double(Textus::Schemas) }
  let(:mentry)     { instance_double(Textus::Manifest::Entry::Base, schema: "person") }
  let(:resolution) { instance_double(Textus::Manifest::Resolver::Resolution, entry: mentry) }
  let(:resolver)   { instance_double(Textus::Manifest::Resolver) }
  let(:manifest)   { instance_double(Textus::Manifest, resolver: resolver) }

  def eval_with(envelope:, target: "working.person.pat")
    Textus::Domain::Policy::Evaluation.new(
      actor: "human", transition: :accept, origin: "review.x",
      target: target, envelope: envelope, snapshot: manifest
    )
  end

  before do
    allow(resolver).to receive(:resolve).with("working.person.pat").and_return(resolution)
    allow(schemas).to receive(:fetch_or_nil).with("person").and_return(schema)
  end

  it "exposes the canonical predicate name" do
    expect(described_class.new(schemas: schemas).name).to eq("schema_valid")
  end

  it "passes when the proposal frontmatter satisfies the target schema" do
    allow(schema).to receive(:validate!).and_return(true)
    env = instance_double(Textus::Envelope, meta: { "frontmatter" => { "name" => "Pat" } })
    expect(described_class.new(schemas: schemas).call(eval_with(envelope: env))).to be(true)
  end

  it "fails and humanizes missing required fields" do
    allow(schema).to receive(:validate!)
      .and_raise(Textus::SchemaViolation.new({ "missing" => ["name"] }))
    env = instance_double(Textus::Envelope, meta: { "frontmatter" => {} })
    pred = described_class.new(schemas: schemas)
    expect(pred.call(eval_with(envelope: env))).to be(false)
    expect(pred.reason).to eq("missing required fields: name")
  end

  it "passes (no-op) when there is no envelope yet" do
    expect(described_class.new(schemas: schemas).call(eval_with(envelope: nil))).to be(true)
  end
end
