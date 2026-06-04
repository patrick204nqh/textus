# frozen_string_literal: true

require "spec_helper"

RSpec.describe Textus::Ports::AuditSubscriber do
  let(:tmpdir)    { Dir.mktmpdir }
  let(:audit_log) { Textus::Ports::AuditLog.new(tmpdir) }
  let(:bus)       { Textus::Hooks::EventBus.new }
  let(:ctx)       { double("ctx") } # rubocop:disable RSpec/VerifiedDoubles

  after { FileUtils.remove_entry(tmpdir) }

  def audit_path
    Textus::Layout.audit_log(tmpdir)
  end

  def read_rows
    return [] unless File.exist?(audit_path)

    File.readlines(audit_path).map { |l| JSON.parse(l.chomp) }
  end

  it "appends an event_error row when a user hook raises" do
    described_class.new(audit_log).attach(bus)
    bus.register(:entry_put, :boom) { |**| raise "bang" }
    bus.publish(:entry_put, key: "k", envelope: {}, ctx: ctx)

    rows = read_rows
    expect(rows.size).to eq(1)
    row = rows.first
    expect(row).to include(
      "role" => "automation",
      "verb" => "event_error",
      "key" => "k",
      "etag_before" => nil,
      "etag_after" => nil,
    )
    expect(row["extras"]).to eq(
      "event" => "entry_put",
      "hook" => "boom",
      "error" => "RuntimeError: bang",
    )
  end

  it "appends an event_error row when a hook times out" do
    described_class.new(audit_log).attach(bus)
    # Override the deadline so the test runs fast.
    stub_const("Textus::Hooks::EventBus::HOOK_TIMEOUT_SECONDS", 0.05)
    bus.register(:entry_put, :slow) { |**| sleep 1 }
    bus.publish(:entry_put, key: "k", envelope: {}, ctx: ctx)

    row = read_rows.first
    expect(row).to include(
      "role" => "automation",
      "verb" => "event_error",
      "key" => "k",
    )
    expect(row["extras"]).to include(
      "event" => "entry_put",
      "hook" => "slow",
    )
    expect(row.dig("extras", "error")).to start_with("Textus::Hooks::EventBus::HookTimeout:")
  end

  it "matches the canonical row format (key ordering and field set)" do
    described_class.new(audit_log).attach(bus)
    bus.register(:entry_put, :boom) { |**| raise "bang" }
    bus.publish(:entry_put, key: "k", envelope: {}, ctx: ctx)

    line = File.read(audit_path).lines.first.chomp
    parsed = JSON.parse(line)
    expect(parsed.keys).to eq(%w[seq ts role verb key etag_before etag_after extras])
  end

  it "writes nothing when a hook succeeds" do
    described_class.new(audit_log).attach(bus)
    bus.register(:entry_put, :ok) { |**| :fine }
    bus.publish(:entry_put, key: "k", envelope: {}, ctx: ctx)

    expect(read_rows).to eq([])
  end

  it "Bus itself writes nothing to audit (sentinel audit_log on success)" do
    sentinel = Class.new do
      def append(**)
        raise "audit_log should not be called by Bus"
      end
    end.new
    # Subscriber wraps sentinel but is never triggered on success path.
    described_class.new(sentinel).attach(bus)
    bus.register(:entry_put, :ok) { |**| :fine }
    expect { bus.publish(:entry_put, key: "k", envelope: {}, ctx: ctx) }.not_to raise_error
  end
end
