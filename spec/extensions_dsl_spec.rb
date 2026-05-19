require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe "Textus DSL verbs" do # rubocop:disable RSpec/MultipleDescribes
  let(:reg)  { Textus::ExtensionRegistry.new }
  let(:noop) { proc { :noop } }

  context "inside with_registry" do
    around do |ex|
      Textus.with_registry(reg) { ex.run }
    end

    it "Textus.fetcher registers into the current registry" do
      Textus.fetcher(:gh) { |config:, store:| [config, store, { frontmatter: {}, body: "ok" }].last }
      out = reg.fetcher(:gh).call(config: {}, store: nil)
      expect(out[:body]).to eq("ok")
    end

    it "Textus.reducer registers into the current registry" do
      Textus.reducer(:top) { |rows:, config:| [config, rows.first(2)].last }
      expect(reg.reducer(:top).call(rows: [1, 2, 3, 4], config: nil)).to eq([1, 2])
    end

    it "Textus.hook registers into the current registry" do
      fired = []
      Textus.hook(:refresh, :notify) { |key:, envelope:, store:, change:| fired << [key, envelope, store, change].first }
      reg.hooks(:refresh).first[:callable].call(key: "x", envelope: {}, store: nil, change: :created)
      expect(fired).to eq(["x"])
    end

    it "isolates registries across threads" do
      other = Textus::ExtensionRegistry.new
      Textus.with_registry(other) do
        Textus.fetcher(:o, &noop)
      end
      expect(other.fetcher_names).to eq([:o])
      expect(reg.fetcher_names).to eq([])
    end
  end

  context "outside with_registry" do
    it "raises usage error" do
      expect { Textus.fetcher(:naked, &noop) }
        .to raise_error(Textus::UsageError, /no active registry/)
    end
  end
end

RSpec.describe "Store-scoped extension loading" do
  let(:tmp)  { Dir.mktmpdir }
  let(:root) { File.join(tmp, ".textus") }

  before do
    FileUtils.mkdir_p(File.join(root, "zones/working"))
    FileUtils.mkdir_p(File.join(root, "extensions"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/1
      zones: [{ name: working, writable_by: [human] }]
      entries:
        - { key: working.x, path: working/x.md, zone: working }
    YAML
    File.write(File.join(root, "extensions/greet.rb"), <<~RUBY)
      Textus.fetcher(:greet) { |config:, store:| [config, store, { frontmatter: { "name" => "x" }, body: "hi" }].last }
      Textus.reducer(:noop)  { |rows:, config:| [config, rows].last }
      Textus.hook(:put, :tap) { |key:, envelope:, store:| [key, envelope, store] }
    RUBY
  end

  after { FileUtils.remove_entry(tmp) }

  it "loads .textus/extensions/*.rb into the store's own registry" do
    store = Textus::Store.new(root)
    expect(store.registry.fetcher_names).to include(:greet)
    expect(store.registry.reducer_names).to include(:noop)
    expect(store.registry.hooks(:put).map { |h| h[:name] }).to include(:tap)
  end

  it "two stores have isolated registries" do
    s1 = Textus::Store.new(root)
    s2 = Textus::Store.new(root)
    expect(s1.registry).not_to be(s2.registry)
    expect(s1.registry.fetcher_names).to eq(s2.registry.fetcher_names)
  end
end
