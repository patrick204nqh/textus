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

  # Builds the explicit-caps kwargs that every Writes use case takes from
  # an explicit store + slim Context pair.
  def writes_caps(store, ctx)
    _, write_caps, hook_caps = Textus::Application.caps_from_store(store)
    reader = build_envelope_reader(store)
    writer = build_envelope_writer(store, ctx, reader: reader)
    # Build ops using the provided ctx so hook_context carries the same correlation_id.
    read_caps, = Textus::Application.caps_from_store(store)
    sess = Textus::Session.new(
      ctx: ctx,
      read_caps: read_caps,
      write_caps: write_caps,
      hook_caps: hook_caps,
    )
    {
      ctx: ctx,
      caps: write_caps,
      rpc: hook_caps.rpc,
      reader: reader,
      writer: writer,
      hook_context: sess.hook_context,
      session: sess,
    }
  end

  def build_put(store, ctx)
    p = writes_caps(store, ctx)
    read_caps, write_caps, hook_caps = Textus::Application.caps_from_store(store)
    container = Textus::Container.from_store_caps(read_caps, write_caps, hook_caps)
    call_value = Textus::Call.new(
      role: ctx.role, correlation_id: ctx.correlation_id,
      now: ctx.now, dry_run: ctx.dry_run
    )
    Textus::Application::Write::Put.new(
      container: container, call: call_value, hook_context: p[:hook_context],
    )
  end

  def build_delete(store, ctx)
    p = writes_caps(store, ctx)
    read_caps, write_caps, hook_caps = Textus::Application.caps_from_store(store)
    container = Textus::Container.from_store_caps(read_caps, write_caps, hook_caps)
    call_value = Textus::Call.new(
      role: ctx.role, correlation_id: ctx.correlation_id,
      now: ctx.now, dry_run: ctx.dry_run
    )
    Textus::Application::Write::Delete.new(
      container: container, call: call_value, hook_context: p[:hook_context],
    )
  end

  def build_mv(store, ctx)
    p = writes_caps(store, ctx)
    read_caps, write_caps, hook_caps = Textus::Application.caps_from_store(store)
    container = Textus::Container.from_store_caps(read_caps, write_caps, hook_caps)
    call_value = Textus::Call.new(
      role: ctx.role, correlation_id: ctx.correlation_id,
      now: ctx.now, dry_run: ctx.dry_run
    )
    Textus::Application::Write::Mv.new(
      container: container, call: call_value, hook_context: p[:hook_context],
    )
  end

  def build_accept(store, ctx)
    p = writes_caps(store, ctx)
    Textus::Application::Write::Accept::Impl.new(
      ctx: p[:ctx], caps: p[:caps], writer: p[:writer],
      hook_context: p[:hook_context]
    )
  end

  def build_reject(store, ctx)
    p = writes_caps(store, ctx)
    Textus::Application::Write::Reject::Impl.new(
      ctx: p[:ctx], caps: p[:caps], writer: p[:writer],
      hook_context: p[:hook_context]
    )
  end

  def build_worker(store, ctx)
    p = writes_caps(store, ctx)
    Textus::Application::Write::RefreshWorker::Impl.new(
      ctx: p[:ctx], caps: p[:caps], rpc: p[:rpc], writer: p[:writer],
      hook_context: p[:hook_context]
    )
  end

  def build_publish(store, ctx)
    p = writes_caps(store, ctx)
    Textus::Application::Write::Publish::Impl.new(
      ctx: p[:ctx], caps: p[:caps], rpc: p[:rpc],
      session: p[:session],
      hook_context: p[:hook_context]
    )
  end
end

RSpec.configure { |c| c.include TextusSpecHelpers }
