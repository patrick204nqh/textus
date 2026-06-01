require "spec_helper"

RSpec.describe "feeds.machines end-to-end" do
  around { |ex| Dir.mktmpdir { |d| Dir.chdir(d) { ex.run } } }

  before do
    `git init -q . && git commit -q --allow-empty -m init`
    Textus::Init.run(File.join(Dir.pwd, ".textus"))
  end

  let(:store) { Textus::Store.new(File.join(Dir.pwd, ".textus")) }

  # One fetch, all assertions — the scan shells out (brew/runtimes), so we don't
  # repeat it. Guards the allowlist on the ACTUAL scaffolded hook init copies
  # into stores, that the nested `local` leaf is protocol-readable, the tree is
  # gitignored, and nothing leaks secrets.
  it "fetches the local leaf: allowlisted, protocol-readable, AND gitignored" do
    store.as("automation").fetch("feeds.machines.local") # explicit fetch — never per-turn
    content = store.as("automation").get("feeds.machines.local").content

    expect(content.keys).to contain_exactly(
      "git_head", "git_branch", "git_dirty", "repo_root", "captured_at",
      "os", "arch", "ruby_version", "runtimes", "packages", "textus_version", "protocol"
    )
    expect(content["protocol"]).to eq(Textus::PROTOCOL)
    expect(content["textus_version"]).to eq(Textus::VERSION)
    expect(content["runtimes"]).to be_a(Hash) # versions or nil per runtime
    expect(content["packages"]).to be_a(Hash) # counts or nil per manager

    # allowlist discipline: no raw environment, no home-path leak
    expect(content).not_to have_key("env")
    expect(content.to_s).not_to include(ENV.fetch("HOME", "/Users/nobody"))

    expect(`git check-ignore .textus/zones/feeds/machines/local.yaml`.strip).not_to be_empty
  end

  it "rejects an unknown machine leaf with a clear error" do
    expect { store.as("automation").fetch("feeds.machines.nope") }
      .to raise_error(/unknown machine: nope/)
  end
end
