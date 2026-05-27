require "spec_helper"

RSpec.describe "Textus.hook collector" do
  after { Textus.drain_hook_blocks }

  it "queues blocks and Textus.drain_hook_blocks returns them in order" do
    a = ->(_reg) {}
    b = ->(_reg) {}
    Textus.hook(&a)
    Textus.hook(&b)
    expect(Textus.drain_hook_blocks).to eq([a, b])
  end

  it "drain empties the queue" do
    Textus.hook { |_reg| nil }
    Textus.drain_hook_blocks
    expect(Textus.drain_hook_blocks).to eq([])
  end

  it "raises UsageError when called without a block" do
    expect { Textus.hook }.to raise_error(Textus::UsageError, /hook block required/)
  end

  it "no longer exposes Textus.on / Textus.with_registry / Textus.current_registry" do
    expect(Textus).not_to respond_to(:on)
    expect(Textus).not_to respond_to(:with_registry)
    expect(Textus).not_to respond_to(:current_registry)
  end

  describe "Bus#on alias" do
    let(:reg) { Textus::Hooks::Bus.new }

    it "registers an RPC handler" do
      reg.on(:resolve_intake, :gh) do |config:, args:, **|
        [config, args]
        { _meta: {}, body: "x" }
      end
      expect(reg.rpc_names(:resolve_intake)).to include(:gh)
    end

    it "registers a pub-sub listener with keys: filter" do
      reg.on(:entry_put, :tap, keys: ["working.*"]) { |key:, **| key }
      expect(reg.pubsub_handlers(:entry_put).map { |h| h[:name] }).to include(:tap)
    end
  end
end
