require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Textus::Hooks::Loader do
  let(:registry) { Textus::Hooks::Registry.new }
  let(:thread_registry_key_legacy) { :__textus_active_registry__ }

  after { Textus.drain_hook_blocks }

  it "loads two hook files and registers handlers via Textus.hook" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "a.rb"), <<~RUBY)
        Textus.hook do |reg|
          reg.on(:resolve_intake, :a) { |config:, args:, **| [config, args]; { _meta: {}, body: "a" } }
        end
      RUBY
      File.write(File.join(dir, "b.rb"), <<~RUBY)
        Textus.hook do |reg|
          reg.on(:transform_rows, :b) { |rows:, **| rows }
        end
      RUBY

      described_class.new(registry: registry).load_dir(dir)

      expect(registry.rpc_names(:resolve_intake)).to include(:a)
      expect(registry.rpc_names(:transform_rows)).to include(:b)
    end
  end

  it "does not use a thread-local registry" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "a.rb"), <<~RUBY)
        Textus.hook do |reg|
          reg.on(:resolve_intake, :a) { |config:, args:, **| [config, args]; { _meta: {}, body: "a" } }
        end
      RUBY

      described_class.new(registry: registry).load_dir(dir)
      expect(Thread.current.keys).not_to include(thread_registry_key_legacy)
    end
  end

  it "does not cross-contaminate handlers between registries on different threads" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "a.rb"), <<~RUBY)
        Textus.hook do |reg|
          reg.on(:resolve_intake, :iso) { |config:, args:, **| [config, args]; { _meta: {}, body: "x" } }
        end
      RUBY

      reg_a = Textus::Hooks::Registry.new
      reg_b = Textus::Hooks::Registry.new

      t1 = Thread.new { described_class.new(registry: reg_a).load_dir(dir) }
      t1.join
      t2 = Thread.new { described_class.new(registry: reg_b).load_dir(dir) }
      t2.join

      expect(reg_a.rpc_names(:resolve_intake)).to include(:iso)
      expect(reg_b.rpc_names(:resolve_intake)).to include(:iso)
    end
  end

  it "loads cleanly when a hook file does not call Textus.hook" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "noop.rb"), "# nothing to register here\n")
      expect { described_class.new(registry: registry).load_dir(dir) }.not_to raise_error
    end
  end

  it "raises UsageError when a hook file fails to load" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "boom.rb"), "raise 'kaboom'\n")
      expect { described_class.new(registry: registry).load_dir(dir) }
        .to raise_error(Textus::UsageError, /failed loading hook boom\.rb/)
    end
  end

  it "raises UsageError when a queued hook block raises during registration" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "bad.rb"), <<~RUBY)
        Textus.hook { |_reg| raise "explode-in-block" }
      RUBY
      expect { described_class.new(registry: registry).load_dir(dir) }
        .to raise_error(Textus::UsageError, /failed registering hook/)
    end
  end

  it "discards leftover queued blocks before the next load" do
    Textus.hook { |_reg| raise "should not run" }
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "a.rb"), <<~RUBY)
        Textus.hook do |reg|
          reg.on(:resolve_intake, :ok) { |config:, args:, **| [config, args]; { _meta: {}, body: "ok" } }
        end
      RUBY

      expect { described_class.new(registry: registry).load_dir(dir) }.not_to raise_error
      expect(registry.rpc_names(:resolve_intake)).to include(:ok)
    end
  end

  it "is a no-op when the directory does not exist" do
    expect { described_class.new(registry: registry).load_dir("/nonexistent/path") }.not_to raise_error
  end
end
