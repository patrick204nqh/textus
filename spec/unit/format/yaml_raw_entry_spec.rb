# frozen_string_literal: true

require "textus/format/yaml"

RSpec.describe Textus::Format::Yaml do
  describe ".validate_raw_entry!" do
    let(:valid_url_content) do
      {
        "ingested_at" => "2026-06-20T12:00:00Z",
        "content_hash" => "sha256:abc123",
        "source" => { "kind" => "url", "url" => "https://example.com", "label" => "test" },
      }
    end

    it "passes for a valid url entry" do
      parsed = { "content" => valid_url_content, "_meta" => {} }
      expect { described_class.validate_raw_entry!(parsed, "raw") }.not_to raise_error
    end

    it "skips validation for non-raw lanes" do
      expect { described_class.validate_raw_entry!({}, "knowledge") }.not_to raise_error
    end

    it "rejects missing ingested_at" do
      content = valid_url_content.except("ingested_at")
      parsed = { "content" => content, "_meta" => {} }
      expect do
        described_class.validate_raw_entry!(parsed, "raw")
      end.to raise_error(Textus::BadContent, /ingested_at/)
    end

    it "rejects missing content_hash" do
      content = valid_url_content.except("content_hash")
      parsed = { "content" => content, "_meta" => {} }
      expect do
        described_class.validate_raw_entry!(parsed, "raw")
      end.to raise_error(Textus::BadContent, /content_hash/)
    end

    it "rejects invalid source.kind" do
      content = valid_url_content.merge("source" => { "kind" => "database" })
      parsed = { "content" => content, "_meta" => {} }
      expect do
        described_class.validate_raw_entry!(parsed, "raw")
      end.to raise_error(Textus::BadContent, /source\.kind/)
    end

    it "rejects url kind without source.url" do
      content = valid_url_content.merge("source" => { "kind" => "url" })
      parsed = { "content" => content, "_meta" => {} }
      expect do
        described_class.validate_raw_entry!(parsed, "raw")
      end.to raise_error(Textus::BadContent, /source\.url/)
    end
  end
end
