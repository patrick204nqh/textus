require "spec_helper"
require "json"

require_relative "../../examples/claude-plugin/recipes/github_folder"

RSpec.describe "github_folder intake hook" do
  let(:fixtures_dir) { File.expand_path("fixtures", __dir__) }
  let(:registry) { Textus::Hooks::Registry.new }
  let(:prev_fetcher) { TextusRecipes::GithubFolder.fetcher }

  def fixture(name)
    File.read(File.join(fixtures_dir, name))
  end

  before do
    stub = {
      "https://api.github.com/repos/example/repo/git/trees/main?recursive=1" =>
        fixture("github_tree.json"),
      "https://api.github.com/repos/example/repo/git/blobs/sha-skill" =>
        fixture("github_blob_skill_md.json"),
      "https://api.github.com/repos/example/repo/git/blobs/sha-run" =>
        fixture("github_blob_scripts_run_rb.json"),
    }
    prev_fetcher # memoize before swapping
    TextusRecipes::GithubFolder.fetcher = ->(url) { stub.fetch(url) }
    Textus.with_registry(registry) { TextusRecipes::GithubFolder.register }
  end

  after { TextusRecipes::GithubFolder.fetcher = prev_fetcher }

  it "returns a content envelope containing only the files under the configured path" do
    callable = registry.rpc_callable(:resolve_intake, :github_folder)
    result = callable.call(
      store: nil,
      config: { "repo" => "example/repo", "ref" => "main", "path" => "skills/agent-eval" },
      args: {},
    )

    files = result[:content]["files"]
    expect(files.keys).to contain_exactly("SKILL.md", "scripts/run.rb")
    expect(files["SKILL.md"]).to eq("# agent-eval SKILL\n\nDemo content\n")
    expect(files["scripts/run.rb"]).to eq("puts \"hello\"\n")
  end

  it "stamps _meta with source repo, ref, path, and timestamp" do
    callable = registry.rpc_callable(:resolve_intake, :github_folder)
    result = callable.call(
      store: nil,
      config: { "repo" => "example/repo", "ref" => "main", "path" => "skills/agent-eval" },
      args: {},
    )

    meta = result[:_meta]
    expect(meta["source_repo"]).to eq("example/repo")
    expect(meta["source_ref"]).to eq("main")
    expect(meta["source_path"]).to eq("skills/agent-eval")
    expect(meta["fetched_at"]).to match(/\A\d{4}-\d{2}-\d{2}T/)
    expect(meta["file_count"]).to eq(2)
  end

  it "raises a UsageError if config is missing required keys" do
    Textus.with_registry(Textus::Hooks::Registry.new) do
      TextusRecipes::GithubFolder.register
    end
    bad_registry = Textus::Hooks::Registry.new
    Textus.with_registry(bad_registry) { TextusRecipes::GithubFolder.register }
    callable = bad_registry.rpc_callable(:resolve_intake, :github_folder)

    expect do
      callable.call(store: nil, config: { "repo" => "example/repo" }, args: {})
    end.to raise_error(Textus::UsageError, /github_folder.*requires.*ref/)
  end
end
