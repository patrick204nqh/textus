require "spec_helper"

RSpec.describe Textus::Domain::Policy::HandlerAllowlist do
  it "stores handler symbol names" do
    a = described_class.new(handlers: %w[http_get local_file])
    expect(a.handlers).to contain_exactly("http_get", "local_file")
  end

  it "#allows?(handler) returns true for listed handlers" do
    a = described_class.new(handlers: ["http_get"])
    expect(a.allows?("http_get")).to be(true)
    expect(a.allows?(:http_get)).to be(true)
    expect(a.allows?("shell_exec")).to be(false)
  end
end
