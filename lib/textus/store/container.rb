# frozen_string_literal: true

module Textus
  class Store
    class Container
      Infrastructure = Data.define(:file_store, :schemas, :audit_log, :job_store, :geometry)
      Coordination   = Data.define(:manifest, :workflows, :gate, :compositor)

      def self.attribute_names
        @attribute_names ||= [:root] + Infrastructure.members + Coordination.members
      end

      def initialize(infra, coord)
        @infra = infra
        @coord = coord
      end

      attr_reader :infra, :coord

      def root
        @infra.geometry.root
      end

      Infrastructure.members.each do |name|
        define_method(name) { @infra.public_send(name) }
      end

      Coordination.members.each do |name|
        define_method(name) { @coord.public_send(name) }
      end

      def self.build_full(infra, coord_seed)
        temp = new(infra, coord_seed)
        compositor = Store::Compositor.new(temp)
        gate = Textus::Gate.new(temp)
        coord = Coordination.new(
          manifest: coord_seed.manifest,
          workflows: coord_seed.workflows,
          gate:,
          compositor:,
        )
        container = new(infra, coord)
        compositor.instance_variable_set(:@container, container)
        gate.instance_variable_set(:@container, container)
        container
      end
    end
  end
end
