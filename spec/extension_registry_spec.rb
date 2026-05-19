require "spec_helper"

RSpec.describe Textus::ExtensionRegistry do
  let(:reg) { described_class.new }
  let(:noop) { proc { :noop } }

  describe "fetchers" do
    it "registers and looks up a fetcher" do
      reg.register_fetcher(:github_repos) { |config:, store:| [config, store, { frontmatter: {}, body: "" }].last }
      expect(reg.fetcher(:github_repos)).to be_a(Proc)
    end

    it "raises usage error for unknown fetcher" do
      expect { reg.fetcher(:nope) }
        .to raise_error(Textus::UsageError, /unknown fetcher: nope/)
    end

    it "lists registered fetchers by name" do
      reg.register_fetcher(:a, &noop)
      reg.register_fetcher(:b, &noop)
      expect(reg.fetcher_names).to contain_exactly(:a, :b)
    end
  end

  describe "reducers" do
    it "registers and looks up a reducer" do
      reg.register_reducer(:top) { |rows:, config:| [config, rows.first(10)].last }
      expect(reg.reducer(:top)).to be_a(Proc)
    end

    it "raises usage error for unknown reducer" do
      expect { reg.reducer(:nope) }
        .to raise_error(Textus::UsageError, /unknown reducer: nope/)
    end
  end

  describe "hooks" do
    it "registers multiple hooks per event" do
      reg.register_hook(:refresh, :h1, &noop)
      reg.register_hook(:refresh, :h2, &noop)
      expect(reg.hooks(:refresh).map { |h| h[:name] }).to eq(%i[h1 h2])
    end

    it "returns empty array for an event with no hooks" do
      expect(reg.hooks(:build)).to eq([])
    end

    it "rejects unknown event names" do
      expect { reg.register_hook(:nonsense, :h, &noop) }
        .to raise_error(Textus::UsageError, /unknown event: nonsense/)
    end
  end

  describe "duplicate registration" do
    it "raises on duplicate fetcher name" do
      reg.register_fetcher(:dup, &noop)
      expect { reg.register_fetcher(:dup, &noop) }
        .to raise_error(Textus::UsageError, /fetcher 'dup' already registered/)
    end
  end
end
