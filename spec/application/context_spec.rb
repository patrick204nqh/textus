# frozen_string_literal: true

require "spec_helper"

RSpec.describe Textus::Application::Context do # rubocop:disable RSpec/MultipleDescribes
  it "carries role, correlation_id, now, and dry_run" do
    t = Time.utc(2026, 1, 1)
    ctx = described_class.build(role: "agent", correlation_id: "c-1", now: t, dry_run: true)
    expect(ctx.role).to eq("agent")
    expect(ctx.correlation_id).to eq("c-1")
    expect(ctx.now).to eq(t)
    expect(ctx.dry_run?).to be(true)
  end

  it "defaults correlation_id, now, dry_run via .build" do
    ctx = described_class.build(role: "human")
    expect(ctx.correlation_id).to be_a(String)
    expect(ctx.now).to be_a(Time)
    expect(ctx.dry_run?).to be(false)
  end

  it "is frozen" do
    expect(described_class.build(role: "human")).to be_frozen
  end

  it "produces a new instance via with_role" do
    ctx = described_class.build(role: "agent", correlation_id: "c-1")
    elev = ctx.with_role("human")
    expect(elev.role).to eq("human")
    expect(elev.correlation_id).to eq("c-1")
    expect(elev).not_to eq(ctx)
  end

  it "does not expose service-locator methods on the slim public surface" do
    ctx = described_class.build(role: "human")
    %i[manifest schemas file_store audit_log bus authorize_write! authorize_read! can_write? can_read?].each do |m|
      expect(ctx).not_to respond_to(m), "expected slim Context not to respond to ##{m}"
    end
  end

  it ".legacy bridges to a store-backed view (will be deleted by Task 5)" do
    expect(described_class).to respond_to(:legacy)
  end
end

RSpec.describe Textus::Application::LegacyContext do
  let(:store) do
    instance_double(
      Textus::Store,
      manifest: instance_double(Textus::Manifest),
      schemas: :schemas_sentinel,
      file_store: :file_store_sentinel,
      audit_log: :audit_log_sentinel,
      bus: :bus_sentinel,
    )
  end

  it "delegates service-locator methods to the underlying store" do
    legacy = Textus::Application::Context.legacy(store: store, role: "human")
    expect(legacy.schemas).to eq(:schemas_sentinel)
    expect(legacy.file_store).to eq(:file_store_sentinel)
    expect(legacy.audit_log).to eq(:audit_log_sentinel)
    expect(legacy.bus).to eq(:bus_sentinel)
    expect(legacy.store).to be(store)
  end

  it "with_role returns another LegacyContext preserving the store" do
    legacy = Textus::Application::Context.legacy(store: store, role: "agent", correlation_id: "c-1")
    elev = legacy.with_role("human")
    expect(elev).to be_a(described_class)
    expect(elev.role).to eq("human")
    expect(elev.correlation_id).to eq("c-1")
    expect(elev.store).to be(store)
    expect(elev.bus).to eq(:bus_sentinel)
  end
end
