require "spec_helper"

RSpec.describe Textus do
  it "is at gem version 0.11.0" do
    expect(Textus::VERSION).to eq("0.11.0")
  end

  it "speaks protocol textus/3" do
    expect(Textus::PROTOCOL).to eq("textus/3")
  end
end
