# frozen_string_literal: true

require "spec_helper"

RSpec.describe Textus::Domain::Authorizer do
  let(:manifest) do
    instance_double(
      Textus::Manifest,
      zone_writers: %w[human],
      zone_readers: { "working" => :all, "identity" => %w[human] },
    ).tap do |m|
      allow(m).to receive(:permission_for) do |zone|
        Textus::Domain::Permission.new(
          zone: zone,
          write_policy: %w[human],
          read_policy: zone == "identity" ? %w[human] : :all,
        )
      end
    end
  end

  let(:mentry) { instance_double(Textus::Manifest::Entry::Base, zone: "working", key: "working.foo") }

  it "allows a write when role is in zone writers" do
    auth = described_class.new(manifest: manifest)
    expect { auth.authorize_write!(mentry, role: "human") }.not_to raise_error
  end

  it "raises WriteForbidden when role is not in zone writers" do
    auth = described_class.new(manifest: manifest)
    expect { auth.authorize_write!(mentry, role: "agent") }.to raise_error(Textus::WriteForbidden)
  end

  it "allows a read when role is in zone readers" do
    auth = described_class.new(manifest: manifest)
    identity_entry = instance_double(Textus::Manifest::Entry::Base, zone: "identity", key: "identity.x")
    expect { auth.authorize_read!(identity_entry, role: "human") }.not_to raise_error
  end

  it "raises ReadForbidden when role is not in zone readers" do
    auth = described_class.new(manifest: manifest)
    identity_entry = instance_double(Textus::Manifest::Entry::Base, zone: "identity", key: "identity.x")
    expect { auth.authorize_read!(identity_entry, role: "agent") }.to raise_error(Textus::ReadForbidden)
  end

  it "answers can_write? and can_read? without raising" do
    auth = described_class.new(manifest: manifest)
    expect(auth.can_write?("working", role: "human")).to be(true)
    expect(auth.can_write?("working", role: "agent")).to be(false)
    expect(auth.can_read?("working", role: "agent")).to be(true)
    expect(auth.can_read?("identity", role: "agent")).to be(false)
  end
end
