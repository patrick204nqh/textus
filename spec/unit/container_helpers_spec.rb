require "spec_helper"

RSpec.describe Textus::ContainerHelpers do
  let(:manifest) { instance_double(Textus::Manifest) }
  let(:container) do
    instance_double(Textus::Store::Container,
                    manifest: manifest,
                    root: "/store/.textus")
  end
  let(:includer) do
    klass = Class.new do
      include Textus::ContainerHelpers

      attr_reader :container

      def initialize(container)
        @container = container
      end
    end
    klass.new(container)
  end

  it "delegates manifest to container" do
    expect(includer.manifest).to eq(manifest)
  end

  it "derives repo_root as parent of container.root" do
    expect(includer.repo_root).to eq("/store")
  end

  it "exposes store_root as container.root" do
    expect(includer.store_root).to eq("/store/.textus")
  end
end
