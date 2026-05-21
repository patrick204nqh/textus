# frozen_string_literal: true

require "spec_helper"

RSpec.describe Textus::Envelope do
  let(:mentry) do
    instance_double(
      Textus::ManifestEntry,
      zone: "working", owner: "human", format: "markdown", schema: nil,
    )
  end

  it "shapes a markdown envelope with uid pulled from meta" do
    env = Textus::Envelope.build(
      key: "working.x",
      mentry: mentry,
      path: "/tmp/x.md",
      meta: { "name" => "x", "uid" => "0123456789abcdef" },
      body: "hi\n",
      etag: "deadbeef",
    )
    expect(env).to include(
      "protocol" => Textus::PROTOCOL,
      "key" => "working.x",
      "zone" => "working",
      "owner" => "human",
      "format" => "markdown",
      "etag" => "deadbeef",
      "uid" => "0123456789abcdef",
    )
    expect(env["_meta"]).to eq("name" => "x", "uid" => "0123456789abcdef")
    expect(env["body"]).to eq("hi\n")
    expect(env).not_to have_key("content")
  end

  it "includes content only when provided" do
    env = Textus::Envelope.build(
      key: "k", mentry: mentry, path: "/p",
      meta: {}, body: "", etag: "e", content: { "a" => 1 }
    )
    expect(env["content"]).to eq("a" => 1)
  end

  it "returns nil uid when meta has none" do
    env = Textus::Envelope.build(
      key: "k", mentry: mentry, path: "/p",
      meta: { "name" => "k" }, body: "", etag: "e"
    )
    expect(env["uid"]).to be_nil
  end
end
