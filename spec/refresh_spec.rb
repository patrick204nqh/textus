require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Textus::Refresh do
  include_context "textus_store_fixture"

  before do
    FileUtils.mkdir_p(File.join(root, "zones/inbox"))
    FileUtils.mkdir_p(File.join(root, "hooks"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones: [{ name: inbox, writable_by: [script] }]
      entries:
        - key: inbox.repos
          path: inbox/repos.md
          zone: inbox
          intake: { handler: stub_fetch, config: { word: hello } }
        - key: inbox.manual
          path: inbox/manual.md
          zone: inbox
    YAML
    File.write(File.join(root, "hooks/stub.rb"), <<~RUBY)
      Textus.hook(:intake, :stub_fetch) do |config:, store:, args:|
        {
          _meta: { "name" => "repos", "last_refreshed_at" => "2026-01-01T00:00:00Z" },
          body: config["word"]
        }
      end
    RUBY
  end

  it "invokes the action, writes the entry under role=script, returns the envelope" do
    store = Textus::Store.new(root)
    env = described_class.call(store, "inbox.repos", as: "script")
    expect(env["body"]).to eq("hello")
    expect(env["zone"]).to eq("inbox")
    expect(File.exist?(File.join(root, "zones/inbox/repos.md"))).to be true
  end

  it "raises if entry has no intake.handler" do
    store = Textus::Store.new(root)
    expect { described_class.call(store, "inbox.manual", as: "script") }
      .to raise_error(Textus::UsageError, /no intake declared/)
  end

  it "wraps intake in a timeout" do
    File.write(File.join(root, "hooks/stub.rb"), <<~RUBY)
      Textus.hook(:intake, :stub_fetch) { |config:, store:, args:| sleep 100 }
    RUBY
    store = Textus::Store.new(root)
    # Worker enforces FETCH_TIMEOUT_SECONDS; we stub Timeout.timeout to fire immediately.
    allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)
    expect { described_class.call(store, "inbox.repos", as: "script") }
      .to raise_error(Textus::UsageError, /timeout/i)
  end

  context "action return-shape normalization (plan-1.2 §7)" do
    it "accepts {content:} for a format: json entry and writes valid JSON" do
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/3
        zones: [{ name: inbox, writable_by: [script] }]
        entries:
          - key: inbox.repos
            path: inbox/repos.json
            zone: inbox
            format: json
            intake: { handler: stub_fetch, config: {} }
      YAML
      File.write(File.join(root, "hooks/stub.rb"), <<~RUBY)
        Textus.hook(:intake, :stub_fetch) do |config:, store:, args:|
          { content: { "items" => [{ "id" => 1 }, { "id" => 2 }] } }
        end
      RUBY
      store = Textus::Store.new(root)
      env = described_class.call(store, "inbox.repos", as: "script")
      expect(env["format"]).to eq("json")
      path = File.join(root, "zones/inbox/repos.json")
      parsed = JSON.parse(File.read(path))
      expect(parsed["items"]).to eq([{ "id" => 1 }, { "id" => 2 }])
      expect(parsed.dig("_meta", "uid")).to match(/\A[a-f0-9]{12,}\z/)
    end

    it "accepts {body:} for a format: text entry and writes bytes verbatim" do
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/3
        zones: [{ name: inbox, writable_by: [script] }]
        entries:
          - key: inbox.notes
            path: inbox/notes.txt
            zone: inbox
            format: text
            intake: { handler: stub_fetch, config: { msg: hello } }
      YAML
      File.write(File.join(root, "hooks/stub.rb"), <<~RUBY)
        Textus.hook(:intake, :stub_fetch) do |config:, store:, args:|
          { body: "raw bytes\\nline 2\\n" }
        end
      RUBY
      store = Textus::Store.new(root)
      described_class.call(store, "inbox.notes", as: "script")
      expect(File.read(File.join(root, "zones/inbox/notes.txt"))).to eq("raw bytes\nline 2\n")
    end
  end

  it "wraps intake exceptions with the handler name" do
    File.write(File.join(root, "hooks/stub.rb"), <<~RUBY)
      Textus.hook(:intake, :stub_fetch) { |config:, store:, args:| raise "network down" }
    RUBY
    store = Textus::Store.new(root)
    expect { described_class.call(store, "inbox.repos", as: "script") }
      .to raise_error(Textus::UsageError, /intake 'stub_fetch' raised.*network down/)
  end
end
