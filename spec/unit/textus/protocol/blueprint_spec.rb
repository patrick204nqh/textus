RSpec.describe Textus::Protocol::Blueprint do
  subject(:blueprint) do
    described_class.new(
      key: "knowledge.loop.intent",
      lane: "knowledge",
      naming: { alias: "sequential", pattern: "\\A\\d{4}-[a-z][a-z0-9-]*\\z", example: "0003-identity" },
      format: "markdown",
      schema: nil,
      key_grammar: { max_segments: 8, max_segment_len: 64, segment_pattern: "\\A[a-z0-9][a-z0-9-]*\\z" },
      meta_template: "---\n---\n<body>",
      template: { key: "knowledge.loop.intent.0000-example", body: "---\n---\n# 0000-example\n" }
    )
  end

  it "is frozen" do
    expect(blueprint).to be_frozen
  end

  it "exposes key" do
    expect(blueprint.key).to eq("knowledge.loop.intent")
  end

  it "exposes naming alias" do
    expect(blueprint.naming[:alias]).to eq("sequential")
  end
end
