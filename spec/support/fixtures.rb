RSpec.shared_context "textus_store_fixture" do
  let(:tmp)  { Dir.mktmpdir }
  let(:root) { File.join(tmp, ".textus") }
  after { FileUtils.remove_entry(tmp) }
end

module TextusSpecHelpers
  # Builds a slim Application::Context for tests. Callers pass the role
  # (and optionally correlation_id, dry_run) — collaborators come from the
  # store, not from Context.
  def test_ctx(role: "human", correlation_id: nil, dry_run: false)
    Textus::Application::Context.build(
      role: role, correlation_id: correlation_id, dry_run: dry_run,
    )
  end

  def build_envelope_reader(store)
    Textus::Application::Envelope::Reader.new(
      file_store: store.file_store,
      manifest: store.manifest,
    )
  end

  def build_envelope_writer(store, ctx, reader: nil)
    Textus::Application::Envelope::Writer.new(
      file_store: store.file_store,
      manifest: store.manifest,
      schemas: store.schemas,
      audit_log: store.audit_log,
      ctx: ctx,
      reader: reader || build_envelope_reader(store),
    )
  end

  # Builds the explicit-port kwargs that every Writes use case takes from
  # an explicit store + slim Context pair.
  def writes_ports(store, ctx)
    ports = Textus::Application::Ports.from_store(store)
    ops = Textus::Operations.new(ctx: ctx, ports: ports)
    reader = build_envelope_reader(store)
    writer = build_envelope_writer(store, ctx, reader: reader)
    {
      ctx: ctx,
      ports: ports,
      reader: reader,
      writer: writer,
      authorizer: Textus::Domain::Authorizer.new(manifest: store.manifest),
      hook_context: ops.hook_context,
    }
  end

  def build_put(store, ctx)
    p = writes_ports(store, ctx)
    Textus::Application::Writes::Put.new(
      ctx: p[:ctx], ports: p[:ports], writer: p[:writer],
      authorizer: p[:authorizer], hook_context: p[:hook_context]
    )
  end

  def build_delete(store, ctx)
    p = writes_ports(store, ctx)
    Textus::Application::Writes::Delete.new(
      ctx: p[:ctx], ports: p[:ports], writer: p[:writer],
      authorizer: p[:authorizer], hook_context: p[:hook_context]
    )
  end

  def build_mv(store, ctx)
    p = writes_ports(store, ctx)
    Textus::Application::Writes::Mv.new(
      ctx: p[:ctx], ports: p[:ports],
      reader: p[:reader], writer: p[:writer],
      authorizer: p[:authorizer], hook_context: p[:hook_context]
    )
  end

  def build_accept(store, ctx)
    p = writes_ports(store, ctx)
    Textus::Application::Writes::Accept.new(
      ctx: p[:ctx], ports: p[:ports], writer: p[:writer],
      authorizer: p[:authorizer], hook_context: p[:hook_context]
    )
  end

  def build_reject(store, ctx)
    p = writes_ports(store, ctx)
    Textus::Application::Writes::Reject.new(
      ctx: p[:ctx], ports: p[:ports], writer: p[:writer],
      authorizer: p[:authorizer], hook_context: p[:hook_context]
    )
  end

  def build_worker(store, ctx)
    p = writes_ports(store, ctx)
    Textus::Application::Refresh::Worker.new(
      ctx: p[:ctx], ports: p[:ports], writer: p[:writer],
      authorizer: p[:authorizer], hook_context: p[:hook_context]
    )
  end

  def build_publish(store, ctx)
    p = writes_ports(store, ctx)
    Textus::Application::Writes::Publish.new(
      ctx: p[:ctx], ports: p[:ports],
      boot: -> { Textus::Boot.run(store) },
      hook_context: p[:hook_context]
    )
  end
end

RSpec.configure { |c| c.include TextusSpecHelpers }
