RSpec.shared_context "textus_store_fixture" do
  let(:tmp)  { Dir.mktmpdir }
  let(:root) { File.join(tmp, ".textus") }
  after { FileUtils.remove_entry(tmp) }
end
