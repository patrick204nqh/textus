RSpec.shared_context "textus_store_fixture" do
  let(:tmp)  { Dir.mktmpdir }
  let(:root) { File.join(tmp, ".textus") }
  after { FileUtils.remove_entry(tmp) }
end

module TextusSpecHelpers
  def build_envelope_io(ctx)
    Textus::Application::Writes::EnvelopeIO.new(
      file_store: ctx.file_store,
      manifest: ctx.manifest,
      schemas: ctx.schemas,
      audit_log: ctx.audit_log,
      ctx: ctx,
    )
  end
end

RSpec.configure { |c| c.include TextusSpecHelpers }
