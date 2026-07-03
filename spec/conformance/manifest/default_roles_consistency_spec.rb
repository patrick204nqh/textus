require "spec_helper"

RSpec.describe "Protocol::V4::LANES role consistency" do
  it "includes only known role names" do
    known = Textus::Value::Role::NAMES
    roles = Textus::Protocol::V4::LANES.values.flat_map { |r| r[:writers] }.uniq
    expect(roles).to all(satisfy { |n| known.include?(n) })
  end

  it "includes human as a writer somewhere" do
    writers = Textus::Protocol::V4::LANES.values.flat_map { |r| r[:writers] }
    expect(writers).to include("human")
  end
end
