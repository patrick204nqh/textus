require "spec_helper"

RSpec.describe Textus::Protocol::StoreEngine::Pipeline do
  describe ".check_etag" do
    it "returns ctx with etag_before when file exists and if_etag matches" do
      deps = double("deps", file_system: double(exists?: true, etag: "abc"))
      ctx  = described_class::DeleteContext.new(key: "k", if_etag: "abc", path: "/p", etag_before: nil)
      result = described_class.check_etag(ctx, deps)
      expect(result.etag_before).to eq("abc")
    end

    it "returns ctx when file does not exist and if_etag is nil" do
      deps = double("deps", file_system: double(exists?: false))
      ctx  = described_class::DeleteContext.new(key: "k", if_etag: nil, path: "/p", etag_before: nil)
      result = described_class.check_etag(ctx, deps)
      expect(result.etag_before).to be_nil
    end

    it "raises EtagMismatch when if_etag does not match" do
      deps = double("deps", file_system: double(exists?: true, etag: "def"))
      ctx  = described_class::DeleteContext.new(key: "k", if_etag: "abc", path: "/p", etag_before: nil)
      expect { described_class.check_etag(ctx, deps) }
        .to raise_error(Textus::EtagMismatch)
    end

    it "raises EtagMismatch with key, wanted, got in details" do
      deps = double("deps", file_system: double(exists?: true, etag: "def"))
      ctx  = described_class::DeleteContext.new(key: "my.key", if_etag: "abc", path: "/p", etag_before: nil)
      expect { described_class.check_etag(ctx, deps) }
        .to raise_error { |e|
          expect(e.details["key"]).to eq("my.key")
          expect(e.details["wanted"]).to eq("abc")
          expect(e.details["got"]).to eq("def")
        }
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
