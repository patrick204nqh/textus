# spec/integration/step/loader_spec.rb
require "spec_helper"

RSpec.describe Textus::Step::Loader do
  it "discovers and registers fetch, transform, and observe steps by path" do # rubocop:disable RSpec/ExampleLength
    Dir.mktmpdir do |root|
      steps = File.join(root, "steps")
      FileUtils.mkdir_p(File.join(steps, "fetch"))
      FileUtils.mkdir_p(File.join(steps, "transform"))
      FileUtils.mkdir_p(File.join(steps, "observe"))

      File.write(File.join(steps, "fetch", "authority.rb"), <<~RUBY)
        module Textus
          module Step
            class AuthorityFetch < Fetch
              def call(config:, args:, **) = { _meta: {}, body: "ok" }
            end
          end
        end
      RUBY
      File.write(File.join(steps, "transform", "adr_index.rb"), <<~RUBY)
        module Textus
          module Step
            class AdrIndexTransform < Transform
              def call(rows:, config:, **) = { "adrs" => rows }
            end
          end
        end
      RUBY
      File.write(File.join(steps, "observe", "watch.rb"), <<~RUBY)
        module Textus
          module Step
            class WatchObserve < Observe
              def self.event = :entry_written
              def self.match = nil
              def call(key:, **) = key
            end
          end
        end
      RUBY

      registry = Textus::Step::RegistryStore.new
      described_class.new(registry: registry).load_dir(steps)

      expect(registry.names(:fetch)).to include(:authority)
      expect(registry.names(:transform)).to include(:adr_index)
    end
  end

  it "correctly invokes a discovered fetch step" do
    Dir.mktmpdir do |root|
      steps = File.join(root, "steps")
      FileUtils.mkdir_p(File.join(steps, "fetch"))
      File.write(File.join(steps, "fetch", "authority.rb"), <<~RUBY)
        module Textus
          module Step
            class AuthorityFetch < Fetch
              def call(config:, args:, **) = { _meta: {}, body: "ok" }
            end
          end
        end
      RUBY

      registry = Textus::Step::RegistryStore.new
      described_class.new(registry: registry).load_dir(steps)

      expect(registry.invoke(:fetch, :authority, caps: nil, config: {}, args: {})).to eq({ _meta: {}, body: "ok" })
    end
  end

  it "raises when a file's class does not subclass the discovered kind" do
    Dir.mktmpdir do |root|
      steps = File.join(root, "steps")
      FileUtils.mkdir_p(File.join(steps, "fetch"))
      File.write(File.join(steps, "fetch", "wrong.rb"), <<~RUBY)
        module Textus
          module Step
            class WrongStep < Transform
              def call(rows:, config:, **) = rows
            end
          end
        end
      RUBY
      expect { described_class.new(registry: Textus::Step::RegistryStore.new).load_dir(steps) }
        .to raise_error(Textus::UsageError, %r{fetch/wrong\.rb defines a transform step})
    end
  end

  it "raises when #call is missing a required kwarg" do
    Dir.mktmpdir do |root|
      steps = File.join(root, "steps")
      FileUtils.mkdir_p(File.join(steps, "fetch"))
      File.write(File.join(steps, "fetch", "bad.rb"), <<~RUBY)
        module Textus
          module Step
            class BadFetch < Fetch
              def call(config:) = config
            end
          end
        end
      RUBY
      expect { described_class.new(registry: Textus::Step::RegistryStore.new).load_dir(steps) }
        .to raise_error(Textus::UsageError, /must accept kwargs.*args/)
    end
  end

  it "is a no-op when the steps dir is absent" do
    Dir.mktmpdir do |root|
      expect { described_class.new(registry: Textus::Step::RegistryStore.new).load_dir(File.join(root, "steps")) }
        .not_to raise_error
    end
  end
end
