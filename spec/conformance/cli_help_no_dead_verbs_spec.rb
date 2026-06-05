require "spec_helper"

# Guard: `textus --help` must not advertise verbs the dispatcher rejects.
# `textus fetch`/`fetch all` were removed in ADR 0079 and now error.
RSpec.describe "CLI --help advertises no deleted verbs" do
  include_context "textus_store_fixture"
  include_context "cli invocation"

  it "does not list 'textus fetch'" do
    run(["--help"])
    expect(stdout.string).to include("textus get KEY") # sanity: help rendered
    expect(stdout.string).not_to include("textus fetch")
  end
end
