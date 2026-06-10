# frozen_string_literal: true

module Textus
  module Step
    # Combines/reshapes projected rows into an artifact shape. Returns a Hash
    # (the structured payload base) or an Array of rows. Replaces the
    # :transform_rows RPC. (Phase 2 will widen `rows:` to a named `inputs:` map.)
    class Transform < Base
      def self.kind = :transform
      def self.required_kwargs = %i[rows config]
    end
  end
end
