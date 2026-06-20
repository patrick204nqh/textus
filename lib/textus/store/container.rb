# frozen_string_literal: true

require "dry-struct"

module Textus
  # Single capability record handed to every use case. Replaces the
  # ReadCaps/WriteCaps/HookCaps trio from 0.26.x. Built once per Store
  # (see Store#initialize); Store delegates its readers to this record,
  # so this struct is the single source of truth for the field set.
  class Store
    class Container < Dry::Struct
      attribute :manifest,   Value::Types::Any
      attribute :file_store, Value::Types::Any
      attribute :schemas,    Value::Types::Any
      attribute :root,       Value::Types::String
      attribute :audit_log,  Value::Types::Any
      attribute :workflows,  Value::Types::Any
      attribute :gate,       Value::Types::Any

      def with(**attrs) = self.class.new(to_h.merge(attrs))

      def initialize(*)
        super
        freeze
      end
    end
  end
end
