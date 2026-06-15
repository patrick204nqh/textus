require "spec_helper"

RSpec.describe "Entry strategy: serialize_for_put" do
  describe "Markdown" do
    it "uses body as the serialized payload; content is nil" do
      bytes, meta, body, content = Textus::Format::Markdown.serialize_for_put(
        meta: { "name" => "foo" }, body: "hello", content: nil, path: "/x/foo.md",
      )
      expect(bytes).to include("hello")
      expect(bytes).to include("name: foo")
      expect(meta).to eq({ "name" => "foo" })
      expect(body).to eq("hello")
      expect(content).to be_nil
    end
  end

  describe "Json" do
    it "with explicit content: serializes meta+content" do
      bytes, meta, _, content = Textus::Format::Json.serialize_for_put(
        meta: { "name" => "foo" }, body: "", content: { "a" => 1 }, path: "/x/foo.json",
      )
      expect(bytes).to include('"a": 1').or include('"a":1')
      expect(meta).to eq({ "name" => "foo" })
      expect(content).to eq({ "a" => 1 })
    end

    it "with body and no content: parses body" do
      body = '{"_meta":{"name":"foo"},"a":1}'
      bytes, meta, _, content = Textus::Format::Json.serialize_for_put(
        meta: nil, body: body, content: nil, path: "/x/foo.json",
      )
      expect(bytes).to eq(body)
      expect(meta).to eq({ "name" => "foo" })
      expect(content).to eq({ "a" => 1 })
    end

    it "without body or content: raises" do
      expect do
        Textus::Format::Json.serialize_for_put(meta: {}, body: nil, content: nil, path: "/x/foo.json")
      end.to raise_error(Textus::UsageError, /requires content: or body:/)
    end
  end

  describe "Text" do
    it "uses body as bytes; content nil" do
      bytes, _, body, content = Textus::Format::Text.serialize_for_put(
        meta: nil, body: "raw text", content: nil, path: "/x/foo.txt",
      )
      expect(bytes).to eq("raw text\n")
      expect(body).to eq("raw text")
      expect(content).to be_nil
    end
  end
end
