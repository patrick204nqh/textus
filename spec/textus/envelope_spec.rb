# frozen_string_literal: true

require "spec_helper"

RSpec.describe Textus::Envelope do
  describe "protocol stamp" do
    let(:mentry) do
      Struct.new(:zone, :owner, :format, :schema).new("working", "human:self", "markdown", nil)
    end

    it "stamps every envelope with the current PROTOCOL constant" do
      env = described_class.build(
        key: "working.x", mentry: mentry, path: "x.md",
        meta: {}, body: "", etag: "sha256:0"
      )
      expect(env["protocol"]).to eq("textus/3")
      expect(env["protocol"]).to eq(Textus::PROTOCOL)
    end
  end
end
