require "spec_helper"

RSpec.describe Textus::Ports::AuditLog do
  context "when the audit log rotates" do
    # Small max_size to force rotation. Each row is ~150 bytes so ~5 rows fits per file.
    let(:root) { Dir.mktmpdir("textus-audit-rotation-") }
    let(:log) { described_class.new(root, max_size: 600, keep: 3) }

    after { FileUtils.rm_rf(root) }

    def append(n)
      n.times { |i| log.append(role: "human", verb: "put", key: "k.#{i}", etag_before: nil, etag_after: "e#{i}") }
    end

    it "rotates active log to audit.log.1 when size exceeds max_size" do
      append(20)

      expect(File).to exist(File.join(audit_dir_path(root), "audit.log.1"))
      # The active log must be small post-rotation (it might have a few fresh appends after the rotation point).
      expect(File.size(audit_log_path(root))).to be <= 600 * 2
    end

    it "writes a sidecar meta json with min_seq and max_seq" do
      append(20)

      meta_path = File.join(audit_dir_path(root), "audit.log.1.meta.json")
      expect(File).to exist(meta_path)
      meta = JSON.parse(File.read(meta_path))
      expect(meta["min_seq"]).to be >= 1
      expect(meta["max_seq"]).to be >= meta["min_seq"]
      expect(meta).to have_key("rotated_at")
    end

    it "preserves seq continuity across rotation" do
      append(20)

      files = (["audit.log.3", "audit.log.2", "audit.log.1"].map { |n| File.join(audit_dir_path(root), n) } +
               [audit_log_path(root)]).select { |f| File.exist?(f) }
      all_seqs = files.flat_map { |f| File.readlines(f).map { |l| JSON.parse(l)["seq"] } }
      expect(all_seqs).to eq((1..all_seqs.size).to_a)
    end

    it "drops the oldest file when keep is exceeded" do
      append(100)

      expect(File).not_to exist(File.join(audit_dir_path(root), "audit.log.4"))
      # audit.log.3 may or may not exist depending on how many rotations happened; the key invariant
      # is "never more than keep rotated files".
      rotated = Dir.glob(File.join(audit_dir_path(root), "audit.log.*")).reject { |p| p.end_with?(".meta.json") }
      expect(rotated.size).to be <= 3
    end

    it "#min_available_seq returns the lowest seq still on disk" do
      append(100)
      expect(log.min_available_seq).to be > 1 # oldest rotated out
    end

    it "#latest_seq remains correct immediately after rotation (active log may be empty)" do
      append(20)
      # latest_seq must reflect the actual highest seq written so far, even if it sits in audit.log.1 not audit.log
      expect(log.latest_seq).to be >= 1
      expect(log.latest_seq).to eq(20)
    end
  end
end
