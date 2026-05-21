require "spec_helper"

RSpec.describe Textus::Store do
  describe "#load_hooks" do
    it "responds to load_hooks (renamed from load_extensions in 0.8.1)" do
      expect(Textus::Store.instance_methods).to include(:load_hooks)
      expect(Textus::Store.instance_methods).not_to include(:load_extensions)
    end
  end
end
