# frozen_string_literal: true

module Textus
  module Links
    class LinkEdgeStore
      def initialize(database)
        @db = database.respond_to?(:connection) ? database.connection : database
      end

      def record(from_key:, to_key:)
        @db[:link_edges].insert_ignore.insert(from_key: from_key, to_key: to_key)
      end

      def dependents_of(key)
        @db[:link_edges].where(to_key: key).select_map(:from_key)
      end

      def neighbors_of(key)
        from = @db[:link_edges].where(from_key: key).select_map(:to_key)
        to = @db[:link_edges].where(to_key: key).select_map(:from_key)
        (from + to).uniq
      end

      def reachable(key, depth: nil)
        if depth
          @db.fetch(<<~SQL, key, depth).map { |r| r[:k] }
            WITH RECURSIVE reachable(k, d) AS (
              SELECT to_key, 1 FROM link_edges WHERE from_key = ?
              UNION ALL
              SELECT e.to_key, r.d + 1 FROM link_edges e
              JOIN reachable r ON e.from_key = r.k
              WHERE r.d < ?
            )
            SELECT DISTINCT k FROM reachable
          SQL
        else
          @db.fetch(<<~SQL, key).map { |r| r[:k] }
            WITH RECURSIVE reachable(k) AS (
              SELECT to_key FROM link_edges WHERE from_key = ?
              UNION ALL
              SELECT e.to_key FROM link_edges e
              JOIN reachable r ON e.from_key = r.k
            )
            SELECT DISTINCT k FROM reachable
          SQL
        end
      end
    end
  end
end
