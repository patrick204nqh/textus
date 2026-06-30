# frozen_string_literal: true

module Textus
  module Links
    class LinkEdgeStore
      def initialize
        @edges = Hash.new { |h, k| h[k] = Set.new }
      end

      def record(from_key:, to_key:)
        @edges[to_key] << from_key
      end

      def dependents_of(key)
        @edges[key].to_a
      end
    end
  end
end
