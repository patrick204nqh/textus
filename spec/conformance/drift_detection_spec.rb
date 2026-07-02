require "spec_helper"

RSpec.describe "textus/4 conformance — Fixture D: doctor callable" do
  include_context "textus/4 conformance fixture"

  describe "Fixture D — doctor still callable" do
    it "keeps doctor callable while drift moved to workflow artifacts" do
      res = store.with_role(Textus::Value::Role::DEFAULT).doctor
      expect(res["protocol"]).to eq(Textus::PROTOCOL)
      expect(res).to have_key("issues")
    end
  end
end
