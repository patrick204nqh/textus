require "spec_helper"

RSpec.describe Textus::Write::IntakeFetch do
  describe ".invoke" do
    it "invokes :resolve_handler through caps.rpc, passing caps through to the handler" do
      result = { _meta: { "name" => "repos" }, body: "hello" }
      rpc = instance_double(Textus::Hooks::RpcRegistry)
      allow(rpc).to receive(:invoke).and_return(result)
      caps = instance_double(Textus::Container, rpc: rpc)

      returned = described_class.invoke(
        caps: caps, handler: "h",
        config: { "word" => "hi" }, args: { "who" => "patrick" }, label: "fetch"
      )

      expect(returned).to eq(result)
      expect(rpc).to have_received(:invoke).with(
        :resolve_handler, "h",
        caps: caps, config: { "word" => "hi" }, args: { "who" => "patrick" }
      )
    end

    it "maps Timeout::Error to a UsageError naming the label, handler and timeout" do
      rpc = instance_double(Textus::Hooks::RpcRegistry)
      caps = instance_double(Textus::Container, rpc: rpc)
      allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)

      expect do
        described_class.invoke(caps: caps, handler: "h", config: {}, args: {}, label: "fetch")
      end.to raise_error(Textus::UsageError, "fetch 'h' exceeded 30s timeout")
    end
  end
end
