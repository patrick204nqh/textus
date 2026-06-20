require "spec_helper"

RSpec.describe Textus::Value::Envelope do
  let(:mentry) do
    instance_double(
      Textus::Manifest::Entry::Base,
      lane: "working", owner: "human:self", format: "markdown", schema: "note",
    )
  end

  it "raises a type error for an unknown format" do
    expect do
      described_class.build(
        key: "k.v", mentry: instance_double(
          Textus::Manifest::Entry::Base,
          lane: "l", owner: "human", format: "pdf", schema: nil,
        ), path: "/tmp/f", meta: {}, body: "", etag: "abc"
      )
    end.to raise_error(Dry::Struct::Error)
  end

  describe ".build" do
    it "constructs an Envelope with all required fields" do
      env = described_class.build(
        key: "working.foo", mentry: mentry, path: "/x/foo.md",
        meta: { "uid" => "abc123def4561234", "name" => "foo" },
        body: "hello", etag: "deadbeef"
      )

      aggregate_failures do
        expect(env).to be_a(Textus::Value::Envelope)
        expect(env.protocol).to eq(Textus::PROTOCOL)
        expect(env.key).to eq("working.foo")
        expect(env.lane).to eq("working")
        expect(env.owner).to eq("human:self")
        expect(env.path).to eq("/x/foo.md")
        expect(env.format).to eq("markdown")
        expect(env.schema_ref).to eq("note")
        expect(env.uid).to eq("abc123def4561234")
        expect(env.etag).to eq("deadbeef")
        expect(env.meta).to eq({ "uid" => "abc123def4561234", "name" => "foo" })
        expect(env.body).to eq("hello")
        expect(env.content).to be_nil
        expect(env.freshness).to be_nil
      end
    end

    it "extracts content when given" do
      env = described_class.build(
        key: "working.j", mentry: mentry, path: "/x/foo.json",
        meta: {}, body: "", etag: "x", content: { "a" => 1 }
      )
      expect(env.content).to eq({ "a" => 1 })
    end

    it "extracts uid from meta when meta has a uid" do
      env = described_class.build(
        key: "k", mentry: mentry, path: "/x/y",
        meta: { "uid" => "abc" }, body: "", etag: "e"
      )
      expect(env.uid).to eq("abc")
    end

    it "uid is nil when meta has no uid string" do
      env = described_class.build(
        key: "k", mentry: mentry, path: "/x/y",
        meta: { "uid" => 42 }, body: "", etag: "e"
      )
      expect(env.uid).to be_nil
    end
  end

  describe "#to_h_for_wire" do
    it "returns a Hash with string keys in the legacy shape" do
      env = described_class.build(
        key: "working.foo", mentry: mentry, path: "/x/foo.md",
        meta: { "uid" => "u1234567890123456", "name" => "foo" },
        body: "hello", etag: "deadbeef"
      )
      h = env.to_h_for_wire

      aggregate_failures do
        expect(h).to be_a(Hash)
        expect(h.keys).to all(be_a(String))
        expect(h["protocol"]).to eq(Textus::PROTOCOL)
        expect(h["key"]).to eq("working.foo")
        expect(h["lane"]).to eq("working")
        expect(h["owner"]).to eq("human:self")
        expect(h["path"]).to eq("/x/foo.md")
        expect(h["format"]).to eq("markdown")
        expect(h["_meta"]).to eq({ "uid" => "u1234567890123456", "name" => "foo" })
        expect(h["body"]).to eq("hello")
        expect(h["etag"]).to eq("deadbeef")
        expect(h["schema_ref"]).to eq("note")
        expect(h["uid"]).to eq("u1234567890123456")
      end
    end

    it "omits content key when content is nil" do
      env = described_class.build(
        key: "k", mentry: mentry, path: "/x/y",
        meta: {}, body: "x", etag: "e"
      )
      expect(env.to_h_for_wire).not_to have_key("content")
    end

    it "flattens freshness fields into top-level wire keys" do
      env = described_class.build(
        key: "k", mentry: mentry, path: "/x/y",
        meta: {}, body: "x", etag: "e"
      ).with(freshness: Textus::Core::Freshness::Verdict.build(
        stale: true, fetching: false, reason: "ttl exceeded",
      ))
      h = env.to_h_for_wire
      aggregate_failures do
        expect(h["stale"]).to be true
        expect(h["fetching"]).to be false
        expect(h["stale_reason"]).to eq("ttl exceeded")
        expect(h).not_to have_key("freshness")
      end
    end

    it "does not emit gem-side-only freshness fields on the wire" do
      env = described_class.build(
        key: "k", mentry: mentry, path: "/x/y",
        meta: {}, body: "x", etag: "e"
      ).with(freshness: Textus::Core::Freshness::Verdict.build(
        stale: false, fetching: false,
        checked_at: Time.utc(2026, 1, 1), ttl_remaining_ms: 1234
      ))
      h = env.to_h_for_wire
      aggregate_failures do
        expect(h).not_to have_key("checked_at")
        expect(h).not_to have_key("ttl_remaining_ms")
      end
    end

    it "asserts freshness is a Freshness or nil (not a Hash)" do
      env = described_class.build(
        key: "k", mentry: mentry, path: "/x/y",
        meta: {}, body: "x", etag: "e"
      )
      expect(env.freshness).to be_nil

      env2 = env.with(freshness: Textus::Core::Freshness::Verdict.build(stale: false))
      expect(env2.freshness).to be_a(Textus::Core::Freshness::Verdict)
      expect(env2.freshness).not_to be_a(Hash)
    end
  end

  describe "predicates" do
    let(:base_env) do
      described_class.build(
        key: "k", mentry: mentry, path: "/x/y",
        meta: {}, body: "", etag: "e"
      )
    end

    it "stale? returns false when freshness is nil" do
      expect(base_env.stale?).to be false
    end

    it "stale? returns true when freshness.stale is true" do
      env = base_env.with(freshness: Textus::Core::Freshness::Verdict.build(stale: true))
      expect(env.stale?).to be true
    end

    it "fetching? returns false when freshness is nil" do
      expect(base_env.fetching?).to be false
    end

    it "fetching? returns the boolean fetching flag" do
      env = base_env.with(freshness: Textus::Core::Freshness::Verdict.build(stale: true, fetching: true))
      expect(env.fetching?).to be true
    end
  end
end
