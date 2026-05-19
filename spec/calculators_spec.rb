require "spec_helper"

RSpec.describe Textus::Calculators do
  around do |ex|
    snapshot = Textus::Calculators::REGISTRY.dup
    ex.run
    Textus::Calculators::REGISTRY.clear
    Textus::Calculators::REGISTRY.merge!(snapshot)
  end

  it "registers and applies a calculator" do
    Textus::Calculators.register("double", ->(rows) { rows.map { |r| r.merge("n" => r["n"] * 2) } })
    out = Textus::Calculators.apply("double", [{ "n" => 1 }, { "n" => 2 }])
    expect(out).to eq([{ "n" => 2 }, { "n" => 4 }])
  end

  it "times out after 2s" do
    Textus::Calculators.register("slow", ->(_) { sleep 5 })
    expect { Textus::Calculators.apply("slow", []) }
      .to raise_error(Textus::UsageError, /timeout/)
  end

  it "raises on unknown" do
    expect { Textus::Calculators.apply("nope", []) }
      .to raise_error(Textus::UsageError, /unknown/)
  end
end
