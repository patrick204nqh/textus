require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe "Textus::RoleScope#refresh" do
  include_context "textus_store_fixture"

  before do
    FileUtils.mkdir_p(File.join(root, "zones/intake"))
    FileUtils.mkdir_p(File.join(root, "hooks"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones: [{ name: intake, kind: quarantine }]
      entries:
        - key: intake.repos
          kind: intake
          path: intake/repos.md
          zone: intake
          intake: { handler: stub_fetch, config: { word: hello } }
        - key: intake.manual
          kind: leaf
          path: intake/manual.md
          zone: intake
    YAML
    File.write(File.join(root, "hooks/stub.rb"), <<~RUBY)
      Textus.hook do |reg|
        reg.on(:resolve_intake, :stub_fetch) do |caps:, config:, args:|
          {
            _meta: { "name" => "repos", "last_refreshed_at" => "2026-01-01T00:00:00Z" },
            body: config["word"]
          }
        end
      end
    RUBY
  end

  it "invokes the action, writes the entry under role=automation, returns the envelope" do
    store = Textus::Store.new(root)
    env = store.as("automation").refresh("intake.repos")
    expect(env.body).to eq("hello")
    expect(env.zone).to eq("intake")
    expect(File.exist?(File.join(root, "zones/intake/repos.md"))).to be true
  end

  it "raises if entry has no intake.handler" do
    store = Textus::Store.new(root)
    expect { store.as("automation").refresh("intake.manual") }
      .to raise_error(Textus::UsageError, /no intake declared/)
  end

  it "wraps intake in a timeout" do
    File.write(File.join(root, "hooks/stub.rb"), <<~RUBY)
      Textus.hook do |reg|
        reg.on(:resolve_intake, :stub_fetch) { |caps:, config:, args:| sleep 100 }
      end
    RUBY
    store = Textus::Store.new(root)
    # Worker enforces FETCH_TIMEOUT_SECONDS; we stub Timeout.timeout to fire immediately.
    allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)
    expect { store.as("automation").refresh("intake.repos") }
      .to raise_error(Textus::UsageError, /timeout/i)
  end

  context "action return-shape normalization (plan-1.2 §7)" do
    it "accepts {content:} for a format: json entry and writes valid JSON" do
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/3
        zones: [{ name: intake, kind: quarantine }]
        entries:
          - key: intake.repos
            kind: intake
            path: intake/repos.json
            zone: intake
            format: json
            intake: { handler: stub_fetch, config: {} }
      YAML
      File.write(File.join(root, "hooks/stub.rb"), <<~RUBY)
        Textus.hook do |reg|
          reg.on(:resolve_intake, :stub_fetch) do |caps:, config:, args:|
            { content: { "items" => [{ "id" => 1 }, { "id" => 2 }] } }
          end
        end
      RUBY
      store = Textus::Store.new(root)
      env = store.as("automation").refresh("intake.repos")
      expect(env.format).to eq("json")
      path = File.join(root, "zones/intake/repos.json")
      parsed = JSON.parse(File.read(path))
      expect(parsed["items"]).to eq([{ "id" => 1 }, { "id" => 2 }])
      expect(parsed.dig("_meta", "uid")).to match(/\A[a-f0-9]{12,}\z/)
    end

    it "accepts {body:} for a format: text entry and writes bytes verbatim" do
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/3
        zones: [{ name: intake, kind: quarantine }]
        entries:
          - key: intake.notes
            kind: intake
            path: intake/notes.txt
            zone: intake
            format: text
            intake: { handler: stub_fetch, config: { msg: hello } }
      YAML
      File.write(File.join(root, "hooks/stub.rb"), <<~RUBY)
        Textus.hook do |reg|
          reg.on(:resolve_intake, :stub_fetch) do |caps:, config:, args:|
            { body: "raw bytes\\nline 2\\n" }
          end
        end
      RUBY
      store = Textus::Store.new(root)
      store.as("automation").refresh("intake.notes")
      expect(File.read(File.join(root, "zones/intake/notes.txt"))).to eq("raw bytes\nline 2\n")
    end
  end

  it "wraps intake exceptions with the handler name" do
    File.write(File.join(root, "hooks/stub.rb"), <<~RUBY)
      Textus.hook do |reg|
        reg.on(:resolve_intake, :stub_fetch) { |caps:, config:, args:| raise "network down" }
      end
    RUBY
    store = Textus::Store.new(root)
    expect { store.as("automation").refresh("intake.repos") }
      .to raise_error(Textus::UsageError, /intake 'stub_fetch' raised.*network down/)
  end

  describe "Ports::Refresh::Detached" do
    it "runs a refresh through Session when spawned" do
      skip "Process.fork not available on this platform" unless Process.respond_to?(:fork)

      fake_store = instance_double(Textus::Store)
      sess       = instance_spy(Textus::RoleScope)
      fake_lock  = instance_double(Textus::Ports::Refresh::Lock, try_acquire: true, release: nil)

      allow(Textus::Store).to receive(:new).and_return(fake_store)
      allow(fake_store).to receive(:as).with("automation").and_return(sess)
      allow(Textus::Ports::Refresh::Lock).to receive(:new).and_return(fake_lock)
      allow(Process).to receive(:fork) do |&blk|
        blk.call
        12_345
      end
      allow(Process).to receive(:detach)
      allow($stdin).to receive(:close)
      allow($stdout).to receive(:reopen)
      allow($stderr).to receive(:reopen)
      allow(Textus::Ports::Refresh::Detached).to receive(:exit)

      Textus::Ports::Refresh::Detached.spawn(store_root: root, key: "intake.x")

      expect(sess).to have_received(:refresh).with("intake.x")
    end
  end
end
