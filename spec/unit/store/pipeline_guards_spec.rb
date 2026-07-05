require "spec_helper"

RSpec.describe Textus::Protocol::StoreEngine::Pipeline do
  describe ".check_etag" do
    it "returns etag_before when file exists and if_etag matches" do
      fs = double(exists?: true, etag: "abc")
      result = described_class.check_etag("k", "/p", "abc", fs)
      expect(result).to eq("abc")
    end

    it "returns nil when file does not exist and if_etag is nil" do
      fs = double(exists?: false)
      result = described_class.check_etag("k", "/p", nil, fs)
      expect(result).to be_nil
    end

    it "raises EtagMismatch when if_etag does not match" do
      fs = double(exists?: true, etag: "def")
      expect { described_class.check_etag("k", "/p", "abc", fs) }
        .to raise_error(Textus::EtagMismatch)
    end

    it "raises EtagMismatch with key, wanted, got in details" do
      fs = double(exists?: true, etag: "def")
      expect { described_class.check_etag("my.key", "/p", "abc", fs) }
        .to(raise_error do |e|
          expect(e.details["key"]).to eq("my.key")
          expect(e.details["wanted"]).to eq("abc")
          expect(e.details["got"]).to eq("def")
        end)
    end
  end

  describe ".resolve_path" do
    it "delegates to manifest resolver and returns path" do
      resolver = double("resolver", resolve: double(path: "/data/k.md"))
      deps = double("deps", manifest: double(resolver: resolver))
      expect(described_class.resolve_path("knowledge.k", deps)).to eq("/data/k.md")
    end
  end
end
