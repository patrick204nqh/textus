RSpec.describe "Textus::Workflow errors" do
  describe Textus::Workflow::StepFailed do
    it "stores step name and wraps the cause message" do
      cause = RuntimeError.new("network timeout")
      err = described_class.new(:fetch, cause)
      expect(err.step_name).to eq(:fetch)
      expect(err.cause).to eq(cause)
      expect(err.message).to include("fetch")
      expect(err.message).to include("network timeout")
    end
  end

  describe Textus::Workflow::NotFound do
    it "includes the key in the message" do
      err = described_class.new("artifacts.feeds.github.repos")
      expect(err.message).to include("artifacts.feeds.github.repos")
    end
  end
end
