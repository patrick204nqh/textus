require "spec_helper"

RSpec.describe Textus::Contract::Around do
  it "wraps a call, letting a resource adjust inputs and post-process the result" do
    resource = Class.new do
      def wrap(scope:, inputs:, session:) # rubocop:disable Lint/UnusedMethodArgument
        adjusted = inputs.merge(since: 10)
        result = yield(adjusted)
        result.merge("wrapped" => true)
      end
    end.new
    described_class.register(:demo_res, resource)

    out = described_class.with(:demo_res, scope: :scope, inputs: { a: 1 }, session: nil) do |eff|
      expect(eff).to eq(a: 1, since: 10)
      { "ok" => true }
    end
    expect(out).to eq("ok" => true, "wrapped" => true)
  end
end
