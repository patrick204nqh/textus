# frozen_string_literal: true

require "dry-struct"

module Textus
  # Single capability record handed to every use case. Replaces the
  # ReadCaps/WriteCaps/HookCaps trio from 0.26.x. Built once per Store
  # (see Store#initialize); Store delegates its readers to this record,
  # so this struct is the single source of truth for the field set.
  class Container < Dry::Struct
    attribute :manifest,   Types::Any
    attribute :file_store, Types::Any
    attribute :schemas,    Types::Any
    attribute :root,       Types::String
    attribute :audit_log,  Types::Any
    attribute :workflows,  Types::Any
    attribute :gate,       Types::Any

    def with(**attrs) = self.class.new(to_h.merge(attrs))

    def initialize(*)
      super
      freeze
    end
  end
end
