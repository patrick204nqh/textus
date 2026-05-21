require "spec_helper"

RSpec.describe Textus::Store do
  describe "#load_hooks" do
    it "defines load_hooks and not load_extensions (renamed in 0.8.1)" do
      expect { Textus::Store.instance_method(:load_hooks) }.not_to raise_error
      expect { Textus::Store.instance_method(:load_extensions) }.to raise_error(NameError)
    end
  end
end
