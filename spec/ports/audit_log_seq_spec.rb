require "spec_helper"

RSpec.describe Textus::Ports::AuditLog do
  let(:root) { Dir.mktmpdir("textus-audit-seq-") }
  let(:log) { described_class.new(root) }

  after { FileUtils.rm_rf(root) }

  describe "#append seq" do
    it "stamps an incrementing seq on every append, starting at 1" do
      log.append(role: "human", verb: "put", key: "a.b", etag_before: nil, etag_after: "e1")
      log.append(role: "human", verb: "put", key: "a.c", etag_before: nil, etag_after: "e2")

      rows = File.readlines(File.join(root, "audit.log")).map { |l| JSON.parse(l) }
      expect(rows.map { |r| r["seq"] }).to eq([1, 2])
    end

    it "continues seq across process restarts by scanning the tail" do
      log.append(role: "human", verb: "put", key: "a.b", etag_before: nil, etag_after: "e1")
      log2 = described_class.new(root) # fresh instance, same dir
      log2.append(role: "human", verb: "put", key: "a.c", etag_before: nil, etag_after: "e2")

      rows = File.readlines(File.join(root, "audit.log")).map { |l| JSON.parse(l) }
      expect(rows.map { |r| r["seq"] }).to eq([1, 2])
    end
  end

  describe "#latest_seq" do
    it "returns 0 when log is absent, increments after each append" do
      expect(log.latest_seq).to eq(0)
      log.append(role: "human", verb: "put", key: "a.b", etag_before: nil, etag_after: "e1")
      expect(log.latest_seq).to eq(1)
    end
  end
end
