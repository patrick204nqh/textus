# spec/unit/command_spec.rb
require "spec_helper"

RSpec.describe "Textus::Command structs" do
  it "Get carries key and role" do
    cmd = Textus::Command::Get.new(key: "knowledge.note", role: "human")
    expect(cmd.key).to eq("knowledge.note")
    expect(cmd.role).to eq("human")
  end

  it "Put carries all write fields" do
    cmd = Textus::Command::Put.new(
      key: "knowledge.note", meta: {}, body: "hi", content: nil, if_etag: nil, role: "human",
    )
    expect(cmd.key).to eq("knowledge.note")
    expect(cmd.body).to eq("hi")
  end

  it "Doctor carries checks and role" do
    cmd = Textus::Command::Doctor.new(checks: nil, role: "human")
    expect(cmd.role).to eq("human")
  end
end
