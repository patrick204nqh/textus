RSpec.describe Textus::Protocol::Diff do
  describe ".body" do
    it "returns empty hunks for identical texts" do
      result = described_class.body("hello\nworld", "hello\nworld")
      expect(result["type"]).to eq("body")
      expect(result["hunks"]).to be_empty
      expect(result["stats"]).to eq({ "additions" => 0, "deletions" => 0, "hunks" => 0 })
    end

    it "returns empty hunks for empty inputs" do
      result = described_class.body(nil, nil)
      expect(result["hunks"]).to be_empty
    end

    it "returns the correct structure keys" do
      result = described_class.body("a", "b")
      expect(result).to have_key("type")
      expect(result).to have_key("hunks")
      expect(result).to have_key("stats")
      expect(result["stats"]).to have_key("additions")
      expect(result["stats"]).to have_key("deletions")
      expect(result["stats"]).to have_key("hunks")
    end

    it "produces hunks as an array" do
      result = described_class.body("a\nb\nc", "a\nx\nc\nd")
      expect(result["hunks"]).to be_an(Array)
    end
  end

  describe ".meta" do
    it "returns empty when hashes are identical" do
      result = described_class.meta({ "a" => 1 }, { "a" => 1 })
      expect(result["changes"]).to be_empty
    end

    it "detects added keys" do
      result = described_class.meta({}, { "b" => 2 })
      expect(result["changes"]).to include(hash_including("key" => "b", "old" => nil, "new" => 2))
    end

    it "detects removed keys" do
      result = described_class.meta({ "a" => 1 }, {})
      expect(result["changes"]).to include(hash_including("key" => "a", "old" => 1, "new" => nil))
    end

    it "detects changed values" do
      result = described_class.meta({ "a" => 1 }, { "a" => 2 })
      expect(result["changes"]).to include(hash_including("key" => "a", "old" => 1, "new" => 2))
    end

    it "handles nil inputs" do
      result = described_class.meta(nil, nil)
      expect(result["changes"]).to be_empty
    end
  end

  describe ".schema" do
    it "returns type 'schema' instead of 'meta'" do
      result = described_class.schema({ "schema" => "v1" }, { "schema" => "v2" })
      expect(result["type"]).to eq("schema")
    end
  end

  describe ".summary" do
    it "formats additions, deletions, and meta changes" do
      result = described_class.summary({
                                         "body" => { "stats" => { "additions" => 3, "deletions" => 1 } },
                                         "meta" => { "stats" => { "changed" => 2 } },
                                       })
      expect(result).to eq("3+ 1- 2~")
    end

    it "omits sections with no changes" do
      result = described_class.summary({
                                         "body" => { "stats" => { "additions" => 5, "deletions" => 0 } },
                                       })
      expect(result).to eq("5+ 0-")
    end

    it "handles empty results" do
      result = described_class.summary({})
      expect(result).to eq("")
    end
  end
end
