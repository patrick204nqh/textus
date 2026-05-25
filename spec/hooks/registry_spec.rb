require "spec_helper"

RSpec.describe Textus::Hooks::Registry do
  let(:reg) { described_class.new }

  # Reusable hook bodies whose kwargs are referenced so rubocop is happy.
  let(:resolve_intake_body) { ->(store:, config:, args:) { { store: store, config: config, args: args } } }
  let(:transform_rows_body) do
    lambda { |store:, rows:, config:|
      [store, config]
      rows
    }
  end
  let(:entry_put_body) { ->(store:, key:, envelope:) { [store, key, envelope] } }

  describe "EVENTS table" do
    it "freezes the table and exposes mode/args for each event" do
      expect(Textus::Hooks::Registry::EVENTS).to be_frozen
      expect(Textus::Hooks::Registry::EVENTS[:resolve_intake][:mode]).to eq(:rpc)
      expect(Textus::Hooks::Registry::EVENTS[:entry_put][:mode]).to eq(:pubsub)
    end

    it "registers :file_published as a pub-sub event" do
      spec = Textus::Hooks::Registry::EVENTS[:file_published]
      expect(spec).not_to be_nil
      expect(spec[:mode]).to eq(:pubsub)
      expect(spec[:args]).to eq(%i[store key envelope source target])
    end
  end

  describe "RPC hooks (resolve_intake, transform_rows, validate)" do
    it "registers and looks up a resolve_intake hook" do
      reg.register(:resolve_intake, :gh, &resolve_intake_body)
      expect(reg.rpc_callable(:resolve_intake, :gh)).to be_a(Proc)
    end

    it "raises on unknown rpc name" do
      expect { reg.rpc_callable(:resolve_intake, :nope) }
        .to raise_error(Textus::UsageError, /unknown resolve_intake: nope/)
    end

    it "raises on duplicate rpc name within event" do
      reg.register(:transform_rows, :rank, &transform_rows_body)
      expect { reg.register(:transform_rows, :rank, &transform_rows_body) }
        .to raise_error(Textus::UsageError, /transform_rows 'rank' already registered/)
    end

    it "allows the same name across different rpc events" do
      reg.register(:resolve_intake, :rank, &resolve_intake_body)
      expect { reg.register(:transform_rows, :rank, &transform_rows_body) }.not_to raise_error
    end
  end

  describe "pub-sub hooks (entry_put, entry_deleted, entry_refreshed, build_completed, proposal_accepted)" do
    it "registers multiple handlers per event" do
      reg.register(:entry_put, :h1, &entry_put_body)
      reg.register(:entry_put, :h2, &entry_put_body)
      expect(reg.listeners(:entry_put, key: "any.x").map { |h| h[:name] }).to eq(%i[h1 h2])
    end

    it "raises on duplicate (event, name) for pub-sub" do
      reg.register(:entry_put, :h, &entry_put_body)
      expect { reg.register(:entry_put, :h, &entry_put_body) }
        .to raise_error(Textus::UsageError, /entry_put hook 'h' already registered/)
    end

    it "filters by keys: glob" do
      reg.register(:entry_put, :intake_only, keys: ["intake.*"], &entry_put_body)
      reg.register(:entry_put, :global, &entry_put_body)
      names = reg.listeners(:entry_put, key: "working.x").map { |h| h[:name] }
      expect(names).to eq([:global])
      names = reg.listeners(:entry_put, key: "intake.repos").map { |h| h[:name] }
      expect(names).to contain_exactly(:intake_only, :global)
    end
  end

  describe "unknown events" do
    it "raises on register with unknown event" do
      expect { reg.register(:bogus, :h, &entry_put_body) }
        .to raise_error(Textus::UsageError, /unknown event: bogus/)
    end
  end

  describe "shape check at registration" do
    it "rejects rpc callable with wrong kwargs" do
      bad = ->(wrong:) { wrong }
      expect { reg.register(:resolve_intake, :bad, &bad) }
        .to raise_error(Textus::UsageError, /resolve_intake hooks must accept kwargs: store, config, args/)
    end

    it "rejects a hook missing the mandatory store: kwarg" do
      no_store = lambda { |rows:, config:|
        [config]
        rows
      }
      expect { reg.register(:transform_rows, :no_store, &no_store) }
        .to raise_error(Textus::UsageError, /missing: store/)
    end

    it "accepts rpc callable with **kwargs catch-all" do
      catchall = ->(**) { {} }
      expect { reg.register(:resolve_intake, :ok, &catchall) }.not_to raise_error
    end
  end
end
