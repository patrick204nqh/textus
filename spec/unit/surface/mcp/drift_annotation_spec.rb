require "spec_helper"

RSpec.describe Textus::Surface::MCP::DriftAnnotation do
  describe ".apply" do
    it "adds contract_drifted to the pulse result" do
      result = described_class.apply({}, action_name: :pulse, drifted: true, is_read: true, current_etag: "b", previous_etag: "a")
      expect(result["contract_drifted"]).to be(true)
    end

    it "does not add contract_drifted for non-pulse verbs" do
      result = described_class.apply({}, action_name: :get, drifted: true, is_read: true, current_etag: "b", previous_etag: "a")
      expect(result).not_to have_key("contract_drifted")
    end

    it "adds a _warning for a drifted write verb" do
      result = described_class.apply({}, action_name: :put, drifted: true, is_read: false, current_etag: "b", previous_etag: "a")
      expect(result["_warning"]).to include("contract drifted")
    end

    it "does not warn for read verbs even when drifted" do
      result = described_class.apply({}, action_name: :get, drifted: true, is_read: true, current_etag: "b", previous_etag: "a")
      expect(result).not_to have_key("_warning")
    end

    it "does not warn for the boot verb even when drifted" do
      result = described_class.apply({}, action_name: :boot, drifted: true, is_read: false, current_etag: "b", previous_etag: "a")
      expect(result).not_to have_key("_warning")
    end

    it "does nothing when not drifted" do
      result = described_class.apply({}, action_name: :put, drifted: false, is_read: false, current_etag: "a", previous_etag: "a")
      expect(result).not_to have_key("_warning")
      expect(result).not_to have_key("contract_drifted")
    end
  end
end
