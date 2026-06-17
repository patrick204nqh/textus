require "spec_helper"

RSpec.describe Textus::Session do
  subject(:session) do
    described_class.new(role: "agent", cursor: 10, propose_lane: "proposals",
                        contract_etag: "sha256:aaaa")
  end

  it "raises a type error for an invalid role" do
    expect do
      described_class.new(role: "nope", cursor: 0, propose_lane: nil, contract_etag: "abc")
    end.to raise_error(Dry::Struct::Error)
  end

  it "raises a type error for a negative cursor" do
    expect do
      described_class.new(role: "human", cursor: -1, propose_lane: nil, contract_etag: "abc")
    end.to raise_error(Dry::Struct::Error)
  end

  it "advances the cursor immutably" do
    advanced = session.advance_cursor(42)
    expect(advanced.cursor).to eq(42)
    expect(session.cursor).to eq(10)
  end

  it "raises on contract drift when the etag changed" do
    expect { session.check_etag!("sha256:bbbb") }
      .to raise_error(%r{manifest/hooks/schemas})
  end

  it "is a no-op when the etag matches" do
    expect { session.check_etag!("sha256:aaaa") }.not_to raise_error
  end
end
