require "spec_helper"

RSpec.describe Textus::HookRegistry do
  let(:reg) { described_class.new }

  # Reusable hook bodies whose kwargs are referenced so rubocop is happy.
  let(:fetch_body) { ->(store:, config:, args:) { { store: store, config: config, args: args } } }
  let(:reduce_body) do
    lambda { |store:, rows:, config:|
      [store, config]
      rows
    }
  end
  let(:put_body) { ->(store:, key:, envelope:) { [store, key, envelope] } }

  describe "EVENTS table" do
    it "freezes the table and exposes mode/args for each event" do
      expect(Textus::HookRegistry::EVENTS).to be_frozen
      expect(Textus::HookRegistry::EVENTS[:fetch][:mode]).to eq(:rpc)
      expect(Textus::HookRegistry::EVENTS[:put][:mode]).to eq(:pubsub)
    end
  end

  describe "RPC hooks (fetch, reduce, check)" do
    it "registers and looks up a fetch hook" do
      reg.register(:fetch, :gh, &fetch_body)
      expect(reg.rpc_callable(:fetch, :gh)).to be_a(Proc)
    end

    it "raises on unknown rpc name" do
      expect { reg.rpc_callable(:fetch, :nope) }
        .to raise_error(Textus::UsageError, /unknown fetch: nope/)
    end

    it "raises on duplicate rpc name within event" do
      reg.register(:reduce, :rank, &reduce_body)
      expect { reg.register(:reduce, :rank, &reduce_body) }
        .to raise_error(Textus::UsageError, /reduce 'rank' already registered/)
    end

    it "allows the same name across different rpc events" do
      reg.register(:fetch, :rank, &fetch_body)
      expect { reg.register(:reduce, :rank, &reduce_body) }.not_to raise_error
    end
  end

  describe "pub-sub hooks (put, delete, refresh, build, accept)" do
    it "registers multiple handlers per event" do
      reg.register(:put, :h1, &put_body)
      reg.register(:put, :h2, &put_body)
      expect(reg.listeners(:put, key: "any.x").map { |h| h[:name] }).to eq(%i[h1 h2])
    end

    it "raises on duplicate (event, name) for pub-sub" do
      reg.register(:put, :h, &put_body)
      expect { reg.register(:put, :h, &put_body) }
        .to raise_error(Textus::UsageError, /put hook 'h' already registered/)
    end

    it "filters by keys: glob" do
      reg.register(:put, :intake_only, keys: ["intake.*"], &put_body)
      reg.register(:put, :global, &put_body)
      names = reg.listeners(:put, key: "working.x").map { |h| h[:name] }
      expect(names).to eq([:global])
      names = reg.listeners(:put, key: "intake.repos").map { |h| h[:name] }
      expect(names).to contain_exactly(:intake_only, :global)
    end
  end

  describe "unknown events" do
    it "raises on register with unknown event" do
      expect { reg.register(:bogus, :h, &put_body) }
        .to raise_error(Textus::UsageError, /unknown event: bogus/)
    end
  end

  describe "shape check at registration" do
    it "rejects rpc callable with wrong kwargs" do
      bad = ->(wrong:) { wrong }
      expect { reg.register(:fetch, :bad, &bad) }
        .to raise_error(Textus::UsageError, /fetch hooks must accept kwargs: store, config, args/)
    end

    it "rejects a hook missing the mandatory store: kwarg" do
      no_store = lambda { |rows:, config:|
        [config]
        rows
      }
      expect { reg.register(:reduce, :no_store, &no_store) }
        .to raise_error(Textus::UsageError, /missing: store/)
    end

    it "accepts rpc callable with **kwargs catch-all" do
      catchall = ->(**) { {} }
      expect { reg.register(:fetch, :ok, &catchall) }.not_to raise_error
    end
  end
end
