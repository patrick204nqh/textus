require "spec_helper"

RSpec.describe "Textus::Store::UseCaseContainer#read_family" do
  include_context "textus_store_fixture"

  let(:container) do
    store_from_manifest(root, lanes: %w[knowledge], manifest: <<~YAML).container
      version: textus/4
      roles:
        - { name: human, can: [author] }
      lanes:
        - { name: knowledge, kind: canon }
      entries:
        - { key: knowledge.goals, path: knowledge/goals, lane: knowledge, kind: nested, format: markdown }
    YAML
  end

  before do
    base = File.join(container.root, "data/knowledge/goals")
    FileUtils.mkdir_p(base)
    File.write(File.join(base, "north-star.md"), "---\n_meta: {}\n---\nBe useful")
    File.write(File.join(base, "focus.md"),      "---\n_meta: {}\n---\nStay sharp")
  end

  it "returns envelopes for all keys under the prefix" do
    envelopes = container.read_family("knowledge.goals")
    expect(envelopes.map(&:key)).to contain_exactly("knowledge.goals.north-star", "knowledge.goals.focus")
  end

  it "returns an empty array when no entries exist under the prefix" do
    expect(container.read_family("knowledge.missing")).to eq([])
  end
end
