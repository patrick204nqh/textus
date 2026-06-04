require "spec_helper"

RSpec.describe "Doctor checks filter" do
  let(:tmp) { Dir.mktmpdir }

  before { Textus::Init.run(File.join(tmp, ".textus")) }
  after  { FileUtils.remove_entry(tmp) }

  it "Doctor.run accepts a checks: filter and runs only the named check" do
    store = Textus::Store.discover(tmp)
    res = Textus::Doctor.build(container: store.container, checks: ["schemas"])
    expect(res["ok"]).to be true
    codes = res["issues"].map { |i| i["code"] }
    expect(codes.none? { |c| c.start_with?("manifest.") }).to be true
  end

  it "Doctor.run raises UsageError on unknown check name" do
    store = Textus::Store.discover(tmp)
    expect { Textus::Doctor.build(container: store.container, checks: ["bogus"]) }.to raise_error(Textus::UsageError)
  end
end
