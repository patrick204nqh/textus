# frozen_string_literal: true

require "spec_helper"

RSpec.describe Textus::Jobs::Planner do
  it "does not include refresh in the convergence trigger actions" do
    expect(described_class::ACTIONS_BY_TRIGGER["convergence"]).not_to include("refresh")
  end

  it "does not define stale_intake_keys" do
    expect(described_class.private_method_defined?(:stale_intake_keys)).to be(false)
  end
end
