require "spec_helper"

RSpec.describe "feeds.machine end-to-end" do
  around { |ex| Dir.mktmpdir { |d| Dir.chdir(d) { ex.run } } }

  before do
    `git init -q . && git commit -q --allow-empty -m init`
    Textus::Init.run(File.join(Dir.pwd, ".textus"))
  end

  it "fetches, is retrievable via the protocol, AND is gitignored" do
    store = Textus::Store.new(File.join(Dir.pwd, ".textus"))

    store.as("automation").fetch("feeds.machine") # explicit fetch — not per-turn
    env = store.as("automation").get("feeds.machine")
    expect(env).not_to be_nil
    expect(env.content["protocol"]).to eq(Textus::PROTOCOL) # content shape from intake

    expect(`git check-ignore .textus/zones/feeds/machine.yaml`.strip).not_to be_empty
  end
end
