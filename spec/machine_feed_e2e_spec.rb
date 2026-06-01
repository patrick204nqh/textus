require "spec_helper"

RSpec.describe "feeds.machine end-to-end" do
  around { |ex| Dir.mktmpdir { |d| Dir.chdir(d) { ex.run } } }

  before do
    `git init -q . && git commit -q --allow-empty -m init`
    Textus::Init.run(File.join(Dir.pwd, ".textus"))
  end

  let(:store) { Textus::Store.new(File.join(Dir.pwd, ".textus")) }

  it "fetches, is retrievable via the protocol, AND is gitignored" do
    store.as("automation").fetch("feeds.machine") # explicit fetch — not per-turn
    env = store.as("automation").get("feeds.machine")
    expect(env).not_to be_nil
    expect(env.content["protocol"]).to eq(Textus::PROTOCOL) # content shape from intake

    expect(`git check-ignore .textus/zones/feeds/machine.yaml`.strip).not_to be_empty
  end

  # Guards the safe-scalar allowlist on the ACTUAL scaffolded hook (the artifact
  # init copies into stores), not a parallel pure-function mirror.
  it "captures exactly the safe-scalar allowlist and never leaks secrets" do
    store.as("automation").fetch("feeds.machine")
    content = store.as("automation").get("feeds.machine").content

    expect(content.keys).to contain_exactly(
      "git_head", "git_branch", "git_dirty", "repo_root",
      "captured_at", "ruby_version", "os", "textus_version", "protocol"
    )
    expect(content["textus_version"]).to eq(Textus::VERSION)
    expect(content).not_to have_key("env")
    expect(content.values.join).not_to include(ENV.fetch("HOME", "/Users"))
  end
end
