# frozen_string_literal: true

require "dry-struct"

module Textus
  class Store
    class Container < Dry::Struct
      attribute :manifest,   Value::Types.Instance(Manifest)
      attribute :file_store, Value::Types.Instance(Port::Storage::FileStore)
      attribute :schemas,    Value::Types.Instance(Schemas)
      attribute :root,       Value::Types::String
      attribute :audit_log,  Value::Types.Instance(Port::AuditLog)
      attribute :workflows,  Value::Types.Instance(Workflow::Registry)
      attribute :job_store,  Value::Types.Instance(Port::Store)
      attribute :gate,       Value::Types.Instance(Gate).optional
      attribute :compositor, Value::Types.Instance(Store::Compositor).optional
      attribute :geometry,   Value::Types.Instance(Store::Geometry).optional

      def with(**attrs) = self.class.new(to_h.merge(attrs))

      def initialize(*)
        super
        freeze
      end
    end
  end
end
