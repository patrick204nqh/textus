# spec/unit/step/registry_spec.rb
require "spec_helper"

RSpec.describe Textus::Step::Registry do
  let(:registry) { described_class.new }

  def fetch_step(step_name)
    Class.new(Textus::Step::Fetch) do
      define_method(:call) { |config:, args:, **| { _meta: {}, body: "got #{config["bytes"]}/#{args}" } }
    end.new.tap { |s| s.name = step_name }
  end

  it "registers and invokes a fetch step by name" do
    registry.register(fetch_step(:authority))
    result = registry.invoke(:fetch, :authority, caps: double("caps"), config: { "bytes" => "b" }, args: {}) # rubocop:disable RSpec/VerifiedDoubles
    expect(result).to eq({ _meta: {}, body: "got b/{}" })
  end

  it "injects caps only when the step declares it" do
    received = nil
    klass = Class.new(Textus::Step::Transform) do
      define_method(:call) do |caps:, rows:, _config:, **|
        received = caps
        rows
      end
    end
    inst = klass.new.tap { |s| s.name = :pluck }
    registry.register(inst)
    caps = double("caps") # rubocop:disable RSpec/VerifiedDoubles
    registry.invoke(:transform, :pluck, caps: caps, rows: [1], config: {})
    expect(received).to be(caps)
  end

  it "raises on duplicate (kind, name)" do
    registry.register(fetch_step(:dup))
    expect { registry.register(fetch_step(:dup)) }
      .to raise_error(Textus::UsageError, /fetch 'dup' already registered/)
  end

  it "raises invoking an unknown step" do
    expect { registry.invoke(:fetch, :missing, caps: nil, config: {}, args: {}) }
      .to raise_error(Textus::UsageError, /unknown fetch: missing/)
  end

  it "lists registered names by kind" do
    registry.register(fetch_step(:a))
    registry.register(fetch_step(:b))
    expect(registry.names(:fetch)).to contain_exactly(:a, :b)
  end

  it "routes observe steps through the event bus and fires them on publish" do
    seen = []
    klass = Class.new(Textus::Step::Observe) do
      on :entry_written
      define_method(:call) { |key:, **| seen << key }
    end
    registry.register(klass.new.tap { |s| s.name = :watcher })
    registry.publish(:entry_written, ctx: nil, key: "k1", envelope: nil)
    expect(seen).to eq(["k1"])
  end

  it "exposes the shared error_log" do
    expect(registry.error_log).to be_a(Textus::Hooks::ErrorLog)
  end

  it "supports built-in observers registered via #on (internal subscribers)" do
    seen = []
    registry.on(:entry_deleted, :internal) { |key:, **| seen << key }
    registry.publish(:entry_deleted, ctx: nil, key: "gone")
    expect(seen).to eq(["gone"])
  end
end
