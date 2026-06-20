require "spec_helper"

RSpec.describe Textus::Command do
  it "carries verb, params, and role" do
    cmd = described_class.new(verb: :get, params: { key: "knowledge.note" }, role: "human")
    expect(cmd.verb).to eq(:get)
    expect(cmd.params).to eq({ key: "knowledge.note" })
    expect(cmd.role).to eq("human")
  end

  it "provides shorthand accessors for common fields" do
    cmd = described_class.new(verb: :put, params: { key: "x", body: "hi" }, role: "human")
    expect(cmd.key).to eq("x")
    expect(cmd[:body]).to eq("hi")
  end

  it "is frozen" do
    cmd = described_class.new(verb: :get, params: {}, role: "human")
    expect(cmd).to be_frozen
    expect(cmd.params).to be_frozen
  end
end
