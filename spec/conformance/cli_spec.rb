require "spec_helper"
require "stringio"

# Conformance CLI smoke tests over the textus/3 §12 fixture.
RSpec.describe "textus/3 conformance — CLI surface" do
  include_context "textus/3 conformance fixture"

  describe "CLI" do
    it "emits a textus/3 envelope for `get`" do
      out = StringIO.new
      rc = Textus::CLI.run(
        ["get", "knowledge.network.org.jane", "--output=json"],
        stdin: StringIO.new, stdout: out, stderr: StringIO.new, cwd: tmp,
      )
      expect(rc).to eq(0)
      env = JSON.parse(out.string.lines.last)
      expect(env["protocol"]).to eq("textus/3")
      expect(env["key"]).to eq("knowledge.network.org.jane")
    end

    it "returns etag_mismatch when if_etag is stale" do
      out = StringIO.new
      rc = Textus::CLI.run(
        ["put", "knowledge.network.org.jane", "--stdin", "--output=json"],
        stdin: StringIO.new(JSON.generate(
                              "_meta" => { "name" => "jane", "relationship" => "peer", "org" => "acme" },
                              "body" => "updated\n",
                              "if_etag" => "sha256:deadbeef",
                            )),
        stdout: out, stderr: StringIO.new, cwd: tmp
      )
      expect(rc).to eq(1)
      env = JSON.parse(out.string.lines.last)
      expect(env["code"]).to eq("etag_mismatch")
    end
  end

  describe "CLI delete" do
    it "deletes via CLI with --as=human" do
      out = StringIO.new
      rc = Textus::CLI.run(
        ["key", "delete", "knowledge.network.org.jane", "--as=human", "--output=json"],
        stdin: StringIO.new, stdout: out, stderr: StringIO.new, cwd: tmp,
      )
      expect(rc).to eq(0)
      expect(JSON.parse(out.string.lines.last)["deleted"]).to be true
    end

    it "validate-all verb is removed in v0.5; doctor --check=schema_violations replaces it" do
      out = StringIO.new
      err = StringIO.new
      rc = Textus::CLI.run(["validate-all", "--output=json"],
                           stdin: StringIO.new, stdout: out, stderr: err, cwd: tmp)
      expect(rc).not_to eq(0)
      expect(JSON.parse(out.string.lines.last)["code"]).to eq("usage")
    end
  end

  describe "--zone filter on list" do
    it "returns only entries in the named zone" do
      expect(store.as(Textus::Role::DEFAULT).list(zone: "knowledge").map { |r| r["zone"] }.uniq).to eq(["knowledge"])
    end
  end
end
