require "spec_helper"

RSpec.describe Textus::Manifest::Entry::Validators::Events do
  let(:entry) { instance_double(Textus::Manifest::Entry::Base, key: "working.foo", events: events) }

  context "with no events declared" do
    let(:events) { {} }

    it "does not raise" do
      expect { described_class.call(entry) }.not_to raise_error
    end
  end

  context "with a known pubsub event" do
    let(:events) { { "entry_put" => "skill_fanout" } }

    it "does not raise" do
      expect { described_class.call(entry) }.not_to raise_error
    end
  end

  context "with an unknown event name" do
    let(:events) { { "totally_invented" => "x" } }

    it "raises UsageError with the entry key prefix" do
      expect { described_class.call(entry) }
        .to raise_error(Textus::UsageError, /entry 'working.foo': unknown event 'totally_invented'/)
    end
  end
end
