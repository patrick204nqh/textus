require "spec_helper"
require "digest"

RSpec.describe Textus::MCP::Session do
  let(:contract_etag) { Digest::SHA256.hexdigest("contract-bytes") }

  it "carries role, cursor, propose_zone, contract_etag" do
    s = described_class.new(
      role: "agent", cursor: 42, propose_zone: "review", contract_etag: contract_etag,
    )
    expect(s.role).to eq("agent")
    expect(s.cursor).to eq(42)
    expect(s.propose_zone).to eq("review")
    expect(s.contract_etag).to eq(contract_etag)
  end

  it "advances cursor, returning a new session (immutable)" do
    s = described_class.new(role: "agent", cursor: 1, propose_zone: nil, contract_etag: "x")
    s2 = s.advance_cursor(5)
    expect(s.cursor).to eq(1)
    expect(s2.cursor).to eq(5)
  end

  it "raises ContractDrift if checked etag differs" do
    s = described_class.new(role: "agent", cursor: 0, propose_zone: nil, contract_etag: "abc")
    expect { s.check_etag!("def") }.to raise_error(Textus::MCP::ContractDrift)
  end

  it "no-ops when checked etag matches" do
    s = described_class.new(role: "agent", cursor: 0, propose_zone: nil, contract_etag: "abc")
    expect { s.check_etag!("abc") }.not_to raise_error
  end
end
