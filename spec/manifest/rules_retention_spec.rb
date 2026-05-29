require "spec_helper"

RSpec.describe "Textus::Manifest::Rules retention parsing" do
  let(:rules) do
    Textus::Manifest::Rules.parse(
      [{ "match" => "review.**", "retention" => { "expire_after" => "30d" } }],
    )
  end

  it "parses retention into a Domain::Policy::Retention" do
    ret = rules.for("review.notes.x").retention
    expect(ret).to be_a(Textus::Domain::Policy::Retention)
    expect(ret.expire_after).to eq(2_592_000)
  end

  it "returns nil retention for an unmatched key" do
    expect(rules.for("working.notes.x").retention).to be_nil
  end
end
