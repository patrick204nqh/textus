require "spec_helper"

RSpec.describe Textus::Workflow::Helpers do
  let(:helper_object) { Class.new { include Textus::Workflow::Helpers }.new }

  describe "#check_naming" do
    let(:matching_entry) { double(key: "knowledge.intent.0001-north-star") }
    let(:bad_entry) { double(key: "knowledge.intent.North Star.md") }

    it "returns no issues when every entry matches the pattern" do
      issues = helper_object.check_naming(
        [matching_entry],
        pattern: /\A0\d{3}-[a-z0-9-]+\z/,
        code: "loop.naming",
        fix: "rename to NNNN-topic-slug",
      )
      expect(issues).to eq([])
    end

    it "returns a canonical-shaped issue for a non-matching entry" do
      issues = helper_object.check_naming(
        [bad_entry],
        pattern: /\A0\d{3}-[a-z0-9-]+\z/,
        code: "loop.naming",
        fix: "rename to NNNN-topic-slug",
      )

      expect(issues.length).to eq(1)
      expect(issues.first).to include(
        "code" => "loop.naming",
        "level" => "warning",
        "subject" => "knowledge.intent.North Star.md",
        "fix" => "rename to NNNN-topic-slug",
      )
      expect(issues.first["message"]).to be_a(String)
    end
  end
end
