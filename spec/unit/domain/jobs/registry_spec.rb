require "spec_helper"

RSpec.describe Textus::Core::Jobs::Registry do
  subject(:registry) { described_class.new }

  it "registers and looks up a handler by type" do
    handler = ->(**) { :ran }
    registry.register("materialize", handler: handler, max_attempts: 5)
    entry = registry.lookup("materialize")
    expect(entry.handler).to eq(handler)
    expect(entry.max_attempts).to eq(5)
  end

  it "reports whether a type is registered" do
    registry.register("sweep", handler: ->(**) {})
    expect(registry.registered?("sweep")).to be true
    expect(registry.registered?("nope")).to be false
  end

  it "raises a usage error for an unregistered type" do
    expect { registry.lookup("nope") }.to raise_error(Textus::UsageError, /unregistered job type/)
  end

  it "defaults max_attempts to 3" do
    registry.register("re-pull", handler: ->(**) {})
    expect(registry.lookup("re-pull").max_attempts).to eq(3)
  end

  it "stores a required_role per entry, defaulting to nil (any caller)" do
    registry.register("sweep", handler: ->(**) {}, required_role: "automation")
    registry.register("open", handler: ->(**) {})
    expect(registry.lookup("sweep").required_role).to eq("automation")
    expect(registry.lookup("open").required_role).to be_nil
  end
end
