RSpec.describe Textus::Core::Sentinel do
  let(:present_stat) do
    instance_double(Textus::Ports::Storage::FileStat,
                    exists?: true, read: Digest::SHA256.hexdigest("content") && "content")
  end
  let(:absent_stat)  { instance_double(Textus::Ports::Storage::FileStat, exists?: false) }
  let(:changed_stat) do
    instance_double(Textus::Ports::Storage::FileStat, exists?: true, read: "different content")
  end

  let(:sha256) { Digest::SHA256.hexdigest("content") }
  let(:sentinel) { described_class.new(target: "/pub/out.md", source: "/data/in.md", sha256: sha256, mode: :copy) }

  describe "#orphan?" do
    it "is true when target is nil" do
      s = described_class.new(target: nil, source: "/data/in.md", sha256: sha256, mode: :copy)
      expect(s.orphan?(present_stat)).to be true
    end

    it "is true when target file does not exist" do
      expect(sentinel.orphan?(absent_stat)).to be true
    end

    it "is false when target file exists" do
      expect(sentinel.orphan?(present_stat)).to be false
    end
  end

  describe "#drift?" do
    it "is false when the sentinel is an orphan" do
      expect(sentinel.drift?(absent_stat)).to be false
    end

    it "is false when sha256 is nil (no checksum recorded)" do
      s = described_class.new(target: "/pub/out.md", source: "/data/in.md", sha256: nil, mode: :copy)
      expect(s.drift?(present_stat)).to be false
    end

    it "is false when the on-disk sha256 matches the recorded sha256" do
      stat = instance_double(Textus::Ports::Storage::FileStat, exists?: true, read: "content")
      expect(sentinel.drift?(stat)).to be false
    end

    it "is true when the on-disk content differs from the recorded sha256" do
      expect(sentinel.drift?(changed_stat)).to be true
    end
  end
end
