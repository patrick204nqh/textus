require "spec_helper"

RSpec.describe Textus::Domain::Jobs::Job do
  it "derives a stable id from type + args, independent of arg order" do
    a = described_class.new(type: "materialize", args: { "key" => "x", "zone" => "k" })
    b = described_class.new(type: "materialize", args: { "zone" => "k", "key" => "x" })
    expect(a.id).to eq(b.id)
    expect(a.id).to start_with("materialize:")
  end

  it "gives different ids for different args" do
    a = described_class.new(type: "materialize", args: { "key" => "x" })
    b = described_class.new(type: "materialize", args: { "key" => "y" })
    expect(a.id).not_to eq(b.id)
  end

  it "round-trips through to_h / from_h preserving fields" do
    job = described_class.new(
      type: "sweep", args: { "scope" => "knowledge" }, enqueued_by: "automation",
      attempts: 2, max_attempts: 3, last_error: "boom"
    )
    restored = described_class.from_h(job.to_h)
    expect(restored.id).to eq(job.id)
    expect(restored.type).to eq("sweep")
    expect(restored.args).to eq({ "scope" => "knowledge" })
    expect(restored.enqueued_by).to eq("automation")
    expect(restored.attempts).to eq(2)
    expect(restored.max_attempts).to eq(3)
    expect(restored.last_error).to eq("boom")
  end

  it "defaults attempts to 0 and last_error to nil" do
    job = described_class.new(type: "re-pull", args: {})
    expect(job.attempts).to eq(0)
    expect(job.last_error).to be_nil
  end
end
