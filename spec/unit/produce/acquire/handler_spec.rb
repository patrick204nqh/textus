require "spec_helper"

RSpec.describe Textus::Produce::Acquire::Handler do
  describe ".invoke" do
    it "invokes :fetch through caps.steps, passing caps through to the handler" do
      result = { _meta: { "name" => "repos" }, body: "hello" }
      steps = instance_double(Textus::Step::RegistryStore)
      allow(steps).to receive(:invoke).and_return(result)
      caps = instance_double(Textus::Container, steps: steps)

      returned = described_class.invoke(
        caps: caps, handler: "h",
        config: { "word" => "hi" }, args: { "who" => "patrick" }, label: "fetch"
      )

      expect(returned).to eq(result)
      expect(steps).to have_received(:invoke).with(
        :fetch, "h",
        caps: caps, config: { "word" => "hi" }, args: { "who" => "patrick" }
      )
    end

    it "maps Timeout::Error to a UsageError naming the label, handler and timeout" do
      steps = instance_double(Textus::Step::RegistryStore)
      caps = instance_double(Textus::Container, steps: steps)
      allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)

      expect do
        described_class.invoke(caps: caps, handler: "h", config: {}, args: {}, label: "fetch")
      end.to raise_error(Textus::UsageError, "fetch 'h' exceeded 30s timeout")
    end
  end
end
