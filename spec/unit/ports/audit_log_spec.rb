# frozen_string_literal: true

require "spec_helper"

RSpec.describe Textus::Ports::AuditLog do
  include_context "textus_store_fixture"

  let(:log) { described_class.new(root) }

  def write_row(seq:, role: "human", verb: "put", key: "k.x")
    path = Textus::Layout.audit_log(root)
    FileUtils.mkdir_p(File.dirname(path))
    row = { "seq" => seq, "ts" => "2026-01-01T00:00:00Z",
            "role" => role, "verb" => verb, "key" => key,
            "etag_before" => nil, "etag_after" => "abc" }
    File.open(path, "a") { |f| f.puts(JSON.generate(row)) }
  end

  describe "#verify_integrity" do
    it "returns empty for a well-formed log" do
      write_row(seq: 1)
      write_row(seq: 2)
      write_row(seq: 3)
      expect(log.verify_integrity).to be_empty
    end

    it "detects a seq gap (missing row)" do
      write_row(seq: 1)
      write_row(seq: 3)  # seq 2 is missing
      violations = log.verify_integrity
      expect(violations.length).to eq(1)
      expect(violations.first["reason"]).to eq("seq_gap")
      expect(violations.first["detail"]).to match(/expected 2, got 3/)
    end

    it "detects a seq regression (row out of order or overwritten)" do
      write_row(seq: 1)
      write_row(seq: 2)
      write_row(seq: 1)  # regression
      violations = log.verify_integrity
      expect(violations.length).to eq(1)
      expect(violations.first["reason"]).to eq("seq_gap")
      expect(violations.first["detail"]).to match(/expected 3, got 1/)
    end

    it "reports invalid JSON lines as before" do
      path = Textus::Layout.audit_log(root)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "not json\n")
      violations = log.verify_integrity
      expect(violations.first["reason"]).to eq("invalid_json")
    end
  end
end
