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

  # Builds the explicit-port kwargs that every Writes use case takes.
  # Callers pass these in as `**writes_ports(ctx)` plus their own envelope_io
  # (or use the convenience helpers below).
  def writes_ports(ctx, envelope_io: nil)
    {
      ctx: ctx,
      manifest: ctx.manifest,
      file_store: ctx.file_store,
      audit_log: ctx.audit_log,
      envelope_io: envelope_io || build_envelope_io(ctx),
      bus: ctx.bus,
      authorizer: Textus::Domain::Authorizer.new(manifest: ctx.manifest),
      root: ctx.store.root,
      store: ctx.store,
    }
  end

  def build_put(ctx, envelope_io: nil)
    p = writes_ports(ctx, envelope_io: envelope_io)
    Textus::Application::Writes::Put.new(
      ctx: p[:ctx], manifest: p[:manifest], envelope_io: p[:envelope_io],
      bus: p[:bus], authorizer: p[:authorizer], store: p[:store]
    )
  end

  def build_delete(ctx, envelope_io: nil)
    p = writes_ports(ctx, envelope_io: envelope_io)
    Textus::Application::Writes::Delete.new(
      ctx: p[:ctx], manifest: p[:manifest], envelope_io: p[:envelope_io],
      bus: p[:bus], authorizer: p[:authorizer], store: p[:store]
    )
  end

  def build_mv(ctx, envelope_io: nil)
    p = writes_ports(ctx, envelope_io: envelope_io)
    Textus::Application::Writes::Mv.new(
      ctx: p[:ctx], manifest: p[:manifest], file_store: p[:file_store],
      audit_log: p[:audit_log], envelope_io: p[:envelope_io],
      bus: p[:bus], authorizer: p[:authorizer], store: p[:store]
    )
  end

  def build_accept(ctx, envelope_io: nil)
    p = writes_ports(ctx, envelope_io: envelope_io)
    Textus::Application::Writes::Accept.new(
      ctx: p[:ctx], manifest: p[:manifest], file_store: p[:file_store],
      envelope_io: p[:envelope_io], bus: p[:bus],
      authorizer: p[:authorizer], store: p[:store]
    )
  end

  def build_reject(ctx, envelope_io: nil)
    p = writes_ports(ctx, envelope_io: envelope_io)
    Textus::Application::Writes::Reject.new(
      ctx: p[:ctx], manifest: p[:manifest], file_store: p[:file_store],
      envelope_io: p[:envelope_io], bus: p[:bus],
      authorizer: p[:authorizer], store: p[:store]
    )
  end

  def build_build(ctx)
    p = writes_ports(ctx)
    Textus::Application::Writes::Build.new(
      ctx: p[:ctx], manifest: p[:manifest], file_store: p[:file_store],
      bus: p[:bus], root: p[:root], store: p[:store]
    )
  end

  def build_publish(ctx)
    p = writes_ports(ctx)
    Textus::Application::Writes::Publish.new(
      ctx: p[:ctx], manifest: p[:manifest], file_store: p[:file_store],
      bus: p[:bus], root: p[:root], store: p[:store]
    )
  end
end

RSpec.configure { |c| c.include TextusSpecHelpers }
