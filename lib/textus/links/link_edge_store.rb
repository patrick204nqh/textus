# frozen_string_literal: true

module Textus
  module Links
    class LinkEdgeStore
      def initialize(database:)
        @db = database.db
      end

      def record(from_key:, to_key:)
        @db[:link_edges].insert_ignore.insert(from_key: from_key, to_key: to_key)
      end

      def dependents_of(key)
        @db[:link_edges].where(to_key: key).select_map(:from_key)
      end

      def neighbors_of(key)
        from = @db[:link_edges].where(from_key: key).select_map(:to_key)
        to   = @db[:link_edges].where(to_key: key).select_map(:from_key)
        (from + to).uniq
      end

      def reachable(key, depth: nil)
        if depth
          ds = @db[:link_edges]
            .with_recursive(:reachable,
              @db[:link_edges].where(from_key: key).select(:to_key, Sequel.lit("1").as(:d)),
              @db[:link_edges]
                .join(:reachable, from_key: :to_key)
                .where { reachable[:d] < depth }
                .select(:link_edges[:to_key], (Sequel.lit("reachable.d + 1")).as(:d)),
            )
            .from(:reachable)
            .select(:to_key)
            .distinct
          ds.map { |r| r[:to_key] }
        else
          ds = @db[:link_edges]
            .with_recursive(:reachable,
              @db[:link_edges].where(from_key: key).select(:to_key),
              @db[:link_edges].join(:reachable, from_key: :to_key).select(:link_edges[:to_key]),
            )
            .from(:reachable)
            .select(:to_key)
            .distinct
          ds.map { |r| r[:to_key] }
        end
      end
    end
  end
end
