require "spec_helper"

RSpec.describe Textus::DependencyAdapters::McpAdapter do
  it "exposes only the published interface" do
    methods = described_class.public_instance_methods(false)
    expect(methods).to contain_exactly(:server, :tool)
  end
end
