require "spec_helper"

RSpec.describe Textus::Manifest::Schema::Contract do
  def result(raw)
    described_class.call(raw)
  end

  it "passes a valid minimal manifest" do
    raw = {
      "lanes" => [{ "name" => "knowledge", "kind" => "canon" }],
      "entries" => [],
    }
    expect(result(raw)).to be_success
  end

  it "fails when lanes is missing" do
    expect(result({ "entries" => [] })).to be_failure
  end

  it "fails when a lane kind is unknown" do
    raw = { "lanes" => [{ "name" => "x", "kind" => "nope" }], "entries" => [] }
    expect(result(raw)).to be_failure
  end

  it "fails when an entry is missing key" do
    raw = {
      "lanes" => [{ "name" => "k", "kind" => "canon" }],
      "entries" => [{ "lane" => "k" }],
    }
    expect(result(raw)).to be_failure
  end
end
