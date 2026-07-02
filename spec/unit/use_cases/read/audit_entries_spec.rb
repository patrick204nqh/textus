require "spec_helper"

RSpec.describe Textus::UseCases::Read::AuditEntries do
  let(:audit_log) do
    Class.new do
      def min_available_seq = 20
      def scan(**) = []
    end.new
  end
  let(:deps) { Data.define(:manifest, :audit_log).new(manifest: nil, audit_log: audit_log) }
  let(:command) do
    Textus::Dispatch::Contracts::AuditEntries.new(
      key: nil, lane: nil, role: nil, verb: nil, since: nil,
      seq_since: 3, correlation_id: nil, limit: nil
    )
  end

  it "returns a Result that raises the real Textus::CursorExpired when seq_since is below the retention window" do
    result = described_class.call(command, nil, deps)

    expect(result.success?).to be(false)
    expect { Textus::Value::Result.extract(result) }.to raise_error(Textus::CursorExpired) do |err|
      expect(err.requested).to eq(3)
      expect(err.min_available).to eq(20)
    end
  end

  it "returns a success Result of rows when seq_since is within the retention window" do
    command_ok = Textus::Dispatch::Contracts::AuditEntries.new(
      key: nil, lane: nil, role: nil, verb: nil, since: nil,
      seq_since: 25, correlation_id: nil, limit: nil
    )
    result = described_class.call(command_ok, nil, deps)

    expect(result.success?).to be(true)
    expect(Textus::Value::Result.extract(result)).to eq([])
  end
end
