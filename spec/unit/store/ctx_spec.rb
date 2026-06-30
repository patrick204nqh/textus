require "spec_helper"

RSpec.describe Textus::Store::Ctx do
  it "is a Data.define with all ten fields" do
    expect(described_class.members).to contain_exactly(
      :manifest, :file_store, :schemas, :audit_log,
      :job_store, :layout, :link_edge_store, :workflows,
      :event_bus, :pipeline
    )
  end

  it "supports #with for immutable update" do
    ctx = described_class.new(
      manifest: :m, file_store: :fs, schemas: :sc, audit_log: :al,
      job_store: :js, layout: :ly, link_edge_store: :les, workflows: :wf,
      event_bus: :eb, pipeline: nil
    )
    updated = ctx.with(pipeline: :p)
    expect(updated.pipeline).to eq(:p)
    expect(ctx.pipeline).to be_nil
  end
end
