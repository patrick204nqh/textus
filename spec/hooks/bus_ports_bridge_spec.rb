require "spec_helper"

# Integration spec for the `store:` -> `ports:` hook-kwarg deprecation
# bridge. Use cases that fan out to user RPC callables run them through
# `Textus::Hooks::Bus.inject_ports_kwargs`, which:
#
#   - injects `ports:` (preferred) when the callable declares it,
#   - injects `store:` (legacy alias of ports) when the callable still
#     declares the old kwarg, and emits one DeprecationNotice row into
#     `error_log` per (event, hook_name) pair on first sight.
RSpec.describe "Hooks::Bus store -> ports kwarg bridge" do
  let(:error_log) { Textus::Hooks::ErrorLog.new }
  let(:ports)     { :a_ports_value } # opaque — bridge does not introspect it

  before do
    # Reset the class-level deprecation memo so each example starts clean.
    Textus::Hooks::Bus.instance_variable_set(:@ports_store_deprecation_seen, {})
  end

  def deprecation_rows
    error_log.since(-2).select { |r| r[:error_class] == "DeprecationNotice" }
  end

  it "passes ports as `store:` to a legacy callable and logs exactly one deprecation row even on repeat invocation" do
    legacy = ->(store:, config:) { [store, config] }

    kwargs1 = Textus::Hooks::Bus.inject_ports_kwargs(
      legacy, ports: ports, error_log: error_log,
              event: :transform_rows, hook_name: :legacy_one,
              other: { config: { "k" => 1 } }
    )
    expect(legacy.call(**kwargs1)).to eq([ports, { "k" => 1 }])

    # Same (event, hook_name) called again — must NOT emit a second row.
    kwargs2 = Textus::Hooks::Bus.inject_ports_kwargs(
      legacy, ports: ports, error_log: error_log,
              event: :transform_rows, hook_name: :legacy_one,
              other: { config: { "k" => 2 } }
    )
    expect(legacy.call(**kwargs2)).to eq([ports, { "k" => 2 }])

    rows = deprecation_rows
    expect(rows.size).to eq(1)
    expect(rows.first).to include(
      event: :transform_rows,
      hook: :legacy_one,
      error_class: "DeprecationNotice",
    )
    expect(rows.first[:error_message]).to match(/declares `store:`/)
  end

  it "passes ports as `ports:` to a modern callable and emits no deprecation row" do
    modern = ->(ports:, config:) { [ports, config] }

    kwargs = Textus::Hooks::Bus.inject_ports_kwargs(
      modern, ports: ports, error_log: error_log,
              event: :transform_rows, hook_name: :modern_one,
              other: { config: { "k" => 1 } }
    )
    expect(modern.call(**kwargs)).to eq([ports, { "k" => 1 }])

    expect(deprecation_rows).to be_empty
  end

  it "logs once per (event, hook_name) pair — distinct hooks each get their own row" do
    legacy_a = ->(store:, **) { store }
    legacy_b = ->(store:, **) { store }

    Textus::Hooks::Bus.inject_ports_kwargs(
      legacy_a, ports: ports, error_log: error_log,
                event: :validate, hook_name: :hook_a, other: {}
    )
    Textus::Hooks::Bus.inject_ports_kwargs(
      legacy_b, ports: ports, error_log: error_log,
                event: :validate, hook_name: :hook_b, other: {}
    )
    Textus::Hooks::Bus.inject_ports_kwargs(
      legacy_a, ports: ports, error_log: error_log,
                event: :validate, hook_name: :hook_a, other: {}
    )

    names = deprecation_rows.map { |r| r[:hook] }
    expect(names).to contain_exactly(:hook_a, :hook_b)
  end
end
