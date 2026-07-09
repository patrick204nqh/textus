require "spec_helper"
require "stringio"

# Conformance CLI smoke tests over the textus/4 §12 fixture.
RSpec.describe "textus/4 conformance — CLI surface" do
  include_context "textus/4 conformance fixture"

  describe "CLI" do
    it "emits a textus/4 envelope for `get`" do
      out = StringIO.new
      rc = Textus::Surface::CLI.run(
        ["get", "knowledge.evidence.0001-topic", "--output=json"],
        stdin: StringIO.new, stdout: out, stderr: StringIO.new, cwd: tmp,
      )
      expect(rc).to eq(0)
      env = JSON.parse(out.string.lines.last)
      expect(env["protocol"]).to eq("textus/4")
      expect(env["key"]).to eq("knowledge.evidence.0001-topic")
    end

    it "returns etag_mismatch when if_etag is stale" do
      out = StringIO.new
      rc = Textus::Surface::CLI.run(
        ["put", "knowledge.intent.0001-north-star", "--stdin", "--output=json"],
        stdin: StringIO.new(JSON.generate(
                              "_meta" => { "name" => "0001-north-star" },
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
      rc = Textus::Surface::CLI.run(
        ["key", "delete", "knowledge.intent.0001-north-star", "--as=human", "--output=json"],
        stdin: StringIO.new, stdout: out, stderr: StringIO.new, cwd: tmp,
      )
      expect(rc).to eq(0)
      expect(JSON.parse(out.string.lines.last)["deleted"]).to be true
    end

    it "validate-all verb is removed in v0.5; doctor --check=schema_violations replaces it" do
      out = StringIO.new
      err = StringIO.new
      rc = Textus::Surface::CLI.run(["validate-all", "--output=json"],
                                    stdin: StringIO.new, stdout: out, stderr: err, cwd: tmp)
      expect(rc).not_to eq(0)
      expect(JSON.parse(out.string.lines.last)["code"]).to eq("usage")
    end
  end

  describe "--zone filter on list" do
    it "returns only entries in the named zone" do
      result = store.with_role(Textus::Value::Role::DEFAULT).list(lane: "knowledge")
      expect(result["data"].map { |r| r["lane"] }.uniq).to eq(["knowledge"])
    end
  end

  # Guard: `textus --help` must not advertise verbs the dispatcher rejects.
  # `textus fetch`/`fetch all` were removed in ADR 0079 and now error.
  describe "--help advertises no deleted verbs" do
    include_context "textus_store_fixture"
    include_context "cli invocation"

    it "does not list 'textus fetch'" do
      run(["--help"])
      expect(stdout.string).to include("textus get KEY") # sanity: help rendered
      expect(stdout.string).not_to include("textus fetch")
    end
  end
end
