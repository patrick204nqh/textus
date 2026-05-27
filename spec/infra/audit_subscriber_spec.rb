# frozen_string_literal: true

require "spec_helper"
require "json"
require "tmpdir"

RSpec.describe Textus::Infra::AuditSubscriber do
  let(:tmpdir)    { Dir.mktmpdir }
  let(:audit_log) { Textus::Infra::AuditLog.new(tmpdir) }
  let(:bus)       { Textus::Hooks::Dispatcher.new }

  after { FileUtils.remove_entry(tmpdir) }

  def audit_path
    File.join(tmpdir, "audit.log")
  end

  def read_rows
    return [] unless File.exist?(audit_path)

    File.readlines(audit_path).map { |l| JSON.parse(l.chomp) }
  end

  it "appends an event_error row when a user hook raises" do
    described_class.new(audit_log).attach(bus)
    bus.subscribe(:entry_put, :boom) { |**| raise "bang" }
    bus.publish(:entry_put, key: "k", envelope: {})

    rows = read_rows
    expect(rows.size).to eq(1)
    row = rows.first
    expect(row).to include(
      "role" => "runner",
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
    stub_const("Textus::Hooks::Dispatcher::HOOK_TIMEOUT_SECONDS", 0.05)
    bus.subscribe(:entry_put, :slow) { |**| sleep 1 }
    bus.publish(:entry_put, key: "k", envelope: {})

    row = read_rows.first
    expect(row).to include(
      "role" => "runner",
      "verb" => "event_error",
      "key" => "k",
    )
    expect(row["extras"]).to include(
      "event" => "entry_put",
      "hook" => "slow",
    )
    expect(row.dig("extras", "error")).to start_with("Textus::Hooks::Dispatcher::HookTimeout:")
  end

  it "matches the canonical row format (key ordering and field set)" do
    described_class.new(audit_log).attach(bus)
    bus.subscribe(:entry_put, :boom) { |**| raise "bang" }
    bus.publish(:entry_put, key: "k", envelope: {})

    line = File.read(audit_path).lines.first.chomp
    parsed = JSON.parse(line)
    expect(parsed.keys).to eq(%w[ts role verb key etag_before etag_after extras])
  end

  it "includes target_key/pending_key extras when present in payload" do
    described_class.new(audit_log).attach(bus)
    bus.subscribe(:entry_moved, :boom) { |**| raise "bang" }
    bus.publish(:entry_moved, key: "k", target_key: "tk", pending_key: "pk")

    row = read_rows.first
    expect(row["extras"]).to include(
      "target_key" => "tk",
      "pending_key" => "pk",
    )
  end

  it "writes nothing when a hook succeeds" do
    described_class.new(audit_log).attach(bus)
    bus.subscribe(:entry_put, :ok) { |**| :fine }
    bus.publish(:entry_put, key: "k", envelope: {})

    expect(read_rows).to eq([])
  end

  it "Dispatcher itself writes nothing to audit (sentinel audit_log on success)" do
    sentinel = Class.new do
      def append(**)
        raise "audit_log should not be called by Dispatcher"
      end
    end.new
    # Subscriber wraps sentinel but is never triggered on success path.
    described_class.new(sentinel).attach(bus)
    bus.subscribe(:entry_put, :ok) { |**| :fine }
    expect { bus.publish(:entry_put, key: "k", envelope: {}) }.not_to raise_error
  end
end
