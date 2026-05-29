require "spec_helper"

RSpec.describe Textus::Maintenance do
  it "exposes Plan as a Data class with steps and warnings" do
    plan = described_class::Plan.new(steps: [{ "op" => "mv", "from" => "a", "to" => "b" }], warnings: ["w1"])
    expect(plan.steps).to eq([{ "op" => "mv", "from" => "a", "to" => "b" }])
    expect(plan.warnings).to eq(["w1"])
  end

  it "Plan#to_h returns a JSON-encodable hash" do
    plan = described_class::Plan.new(steps: [], warnings: [])
    expect(plan.to_h).to eq("steps" => [], "warnings" => [])
  end
end
