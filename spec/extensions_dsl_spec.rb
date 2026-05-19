require "spec_helper"

RSpec.describe "Textus DSL verbs" do
  let(:reg) { Textus::ExtensionRegistry.new }
  let(:noop) { proc { :noop } }

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

  it "raises when called outside with_registry" do
    prev = Thread.current[Textus::THREAD_REGISTRY_KEY]
    Thread.current[Textus::THREAD_REGISTRY_KEY] = nil
    begin
      expect { Textus.fetcher(:naked, &noop) }
        .to raise_error(Textus::UsageError, /no active registry/)
    ensure
      Thread.current[Textus::THREAD_REGISTRY_KEY] = prev
    end
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
