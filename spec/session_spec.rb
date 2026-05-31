require "spec_helper"

RSpec.describe Textus::Session do
  subject(:session) do
    described_class.new(role: :agent, cursor: 10, propose_zone: "proposals",
                        manifest_etag: "sha256:aaaa")
  end

  it "advances the cursor immutably" do
    advanced = session.advance_cursor(42)
    expect(advanced.cursor).to eq(42)
    expect(session.cursor).to eq(10)
  end

  it "raises on manifest drift when the etag changed" do
    expect { session.check_etag!("sha256:bbbb") }.to raise_error(/re-run boot/)
  end

  it "is a no-op when the etag matches" do
    expect { session.check_etag!("sha256:aaaa") }.not_to raise_error
  end
end
