require "spec_helper"

RSpec.describe Textus do
  it "is at gem version 0.12.4" do
    expect(Textus::VERSION).to eq("0.12.4")
  end

  it "still speaks protocol textus/3 (unchanged in this release)" do
    expect(Textus::PROTOCOL).to eq("textus/3")
  end
end
