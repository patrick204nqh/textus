# frozen_string_literal: true

require "spec_helper"

RSpec.describe Textus::Jobs do
  it "resolves materialize by type string" do
    # Trigger Zeitwerk to load the subclass before fetching.
    expect(described_class.fetch("materialize")).to eq(Textus::Jobs::Materialize)
  end

  it "resolves refresh by type string" do
    expect(described_class.fetch("refresh")).to eq(Textus::Jobs::Refresh)
  end

  it "resolves sweep by type string" do
    expect(described_class.fetch("sweep")).to eq(Textus::Jobs::Sweep)
  end

  it "raises UsageError for an unknown type" do
    expect { described_class.fetch("ghost") }
      .to raise_error(Textus::UsageError, /unknown job type/)
  end
end
