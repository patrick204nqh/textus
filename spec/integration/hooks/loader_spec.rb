require "spec_helper"

RSpec.describe Textus::Hooks::Loader do
  let(:events)   { Textus::Hooks::EventBus.new }
  let(:rpc)      { Textus::Hooks::RpcRegistry.new }
  let(:registry) { Textus::Hooks::Loader::Dsl.new(events: events, rpc: rpc) }
  let(:thread_registry_key_legacy) { :__textus_active_registry__ }

  after { Textus.drain_hook_blocks }

  it "loads two hook files and registers handlers via Textus.hook" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "a.rb"), <<~RUBY)
        Textus.hook do |reg|
          reg.on(:resolve_handler, :a) { |config:, args:, **| [config, args]; { _meta: {}, body: "a" } }
        end
      RUBY
      File.write(File.join(dir, "b.rb"), <<~RUBY)
        Textus.hook do |reg|
          reg.on(:transform_rows, :b) { |rows:, **| rows }
        end
      RUBY

      described_class.new(events: events, rpc: rpc).load_dir(dir)

      expect(rpc.names(:resolve_handler)).to include(:a)
      expect(rpc.names(:transform_rows)).to include(:b)
    end
  end

  it "does not use a thread-local registry" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "a.rb"), <<~RUBY)
        Textus.hook do |reg|
          reg.on(:resolve_handler, :a) { |config:, args:, **| [config, args]; { _meta: {}, body: "a" } }
        end
      RUBY

      described_class.new(events: events, rpc: rpc).load_dir(dir)
      expect(Thread.current.keys).not_to include(thread_registry_key_legacy)
    end
  end

  it "does not cross-contaminate handlers between registries on different threads" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "a.rb"), <<~RUBY)
        Textus.hook do |reg|
          reg.on(:resolve_handler, :iso) { |config:, args:, **| [config, args]; { _meta: {}, body: "x" } }
        end
      RUBY

      ev_a = Textus::Hooks::EventBus.new
      rpc_a = Textus::Hooks::RpcRegistry.new
      ev_b = Textus::Hooks::EventBus.new
      rpc_b = Textus::Hooks::RpcRegistry.new

      t1 = Thread.new { described_class.new(events: ev_a, rpc: rpc_a).load_dir(dir) }
      t1.join
      t2 = Thread.new { described_class.new(events: ev_b, rpc: rpc_b).load_dir(dir) }
      t2.join

      expect(rpc_a.names(:resolve_handler)).to include(:iso)
      expect(rpc_b.names(:resolve_handler)).to include(:iso)
    end
  end

  it "loads cleanly when a hook file does not call Textus.hook" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "noop.rb"), "# nothing to register here\n")
      expect { described_class.new(events: events, rpc: rpc).load_dir(dir) }.not_to raise_error
    end
  end

  it "raises UsageError when a hook file fails to load" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "boom.rb"), "raise 'kaboom'\n")
      expect { described_class.new(events: events, rpc: rpc).load_dir(dir) }
        .to raise_error(Textus::UsageError, /failed loading hook boom\.rb/)
    end
  end

  it "raises UsageError when a queued hook block raises during registration" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "bad.rb"), <<~RUBY)
        Textus.hook { |_reg| raise "explode-in-block" }
      RUBY
      expect { described_class.new(events: events, rpc: rpc).load_dir(dir) }
        .to raise_error(Textus::UsageError, /failed registering hook/)
    end
  end

  it "discards leftover queued blocks before the next load" do
    Textus.hook { |_reg| raise "should not run" }
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "a.rb"), <<~RUBY)
        Textus.hook do |reg|
          reg.on(:resolve_handler, :ok) { |config:, args:, **| [config, args]; { _meta: {}, body: "ok" } }
        end
      RUBY

      expect { described_class.new(events: events, rpc: rpc).load_dir(dir) }.not_to raise_error
      expect(rpc.names(:resolve_handler)).to include(:ok)
    end
  end

  it "is a no-op when the directory does not exist" do
    expect { described_class.new(events: events, rpc: rpc).load_dir("/nonexistent/path") }.not_to raise_error
  end
end
