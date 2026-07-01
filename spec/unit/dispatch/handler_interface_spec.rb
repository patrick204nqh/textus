require "spec_helper"

RSpec.describe "dispatch handler interface" do
  it "supports keyword-style command and call invocation" do
    handler = ->(command:, call:) { { command: command.class.name, role: call.role } }

    result = handler.call(
      command: Textus::Dispatch::Contracts::ListKeys.new(prefix: nil, lane: nil, q: nil, schema: nil),
      call: Textus::Value::Call.build(role: "human"),
    )

    expect(result).to include(command: "Textus::Dispatch::Contracts::ListKeys", role: "human")
  end
end
