require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Textus::Refresh do
  let(:tmp)  { Dir.mktmpdir }
  let(:root) { File.join(tmp, ".textus") }

  before do
    FileUtils.mkdir_p(File.join(root, "zones/intake"))
    FileUtils.mkdir_p(File.join(root, "extensions"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/1
      zones: [{ name: intake, writable_by: [script] }]
      entries:
        - key: intake.repos
          path: intake/repos.md
          zone: intake
          source: { fetcher: stub_fetch, config: { word: hello } }
    YAML
    File.write(File.join(root, "extensions/stub.rb"), <<~RUBY)
      Textus.fetcher(:stub_fetch) do |config:, store:|
        {
          frontmatter: { "name" => "repos", "last_refreshed_at" => "2026-01-01T00:00:00Z" },
          body: config["word"]
        }
      end
    RUBY
  end

  after { FileUtils.remove_entry(tmp) }

  it "invokes the fetcher, writes the entry under role=script, returns the envelope" do
    store = Textus::Store.new(root)
    env = described_class.call(store, "intake.repos", as: "script")
    expect(env["body"]).to eq("hello")
    expect(env["zone"]).to eq("intake")
    expect(File.exist?(File.join(root, "zones/intake/repos.md"))).to be true
  end

  it "raises if entry has no source.fetcher" do
    store = Textus::Store.new(root)
    store.manifest.entries.first.instance_variable_set(:@fetcher, nil)
    expect { described_class.call(store, "intake.repos", as: "script") }
      .to raise_error(Textus::UsageError, /no fetcher declared/)
  end

  it "wraps fetcher in 2s timeout" do
    File.write(File.join(root, "extensions/stub.rb"), <<~RUBY)
      Textus.fetcher(:stub_fetch) { |config:, store:| sleep 3 }
    RUBY
    store = Textus::Store.new(root)
    expect { described_class.call(store, "intake.repos", as: "script") }
      .to raise_error(Textus::UsageError, /timeout/i)
  end
end
