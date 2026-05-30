require "spec_helper"

RSpec.describe Textus::Domain::Policy::Predicates::Registry do
  it "builds a parameterless predicate by name" do
    pred = described_class.build("accept_signed", schemas: nil)
    expect(pred.name).to eq("accept_signed")
  end

  it "builds a parameterized predicate from a {name => params} hash" do
    pred = described_class.build({ "fresh_within" => "1h" }, schemas: nil)
    expect(pred.name).to eq("fresh_within")
  end

  it "injects schemas into schema_valid" do
    pred = described_class.build("schema_valid", schemas: :schemas_stub)
    expect(pred.name).to eq("schema_valid")
  end

  it "raises UsageError for an unknown predicate, listing known names" do
    expect { described_class.build("nope", schemas: nil) }
      .to raise_error(Textus::UsageError, /unknown guard predicate: 'nope' \(known:/)
  end
end
