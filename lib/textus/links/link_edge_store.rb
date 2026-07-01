# frozen_string_literal: true

module Textus
  module Links
    class LinkEdgeStore
      def initialize(db:)
        @db = db
      end

      def record(from_key:, to_key:)
        @db.execute(
          "INSERT OR IGNORE INTO link_edges (from_key, to_key) VALUES (?, ?)",
          [from_key, to_key],
        )
      end

      def dependents_of(key)
        @db.execute("SELECT from_key FROM link_edges WHERE to_key = ?", [key])
           .map { |r| r["from_key"] }
      end

      def neighbors_of(key)
        sql = <<~SQL
          SELECT to_key AS key FROM link_edges WHERE from_key = ?
          UNION
          SELECT from_key AS key FROM link_edges WHERE to_key = ?
        SQL
        @db.execute(sql, [key, key]).map { |r| r["key"] }
      end

      def reachable(key, depth: nil)
        if depth
          sql = <<~SQL
            WITH RECURSIVE reachable(k, d) AS (
              SELECT to_key, 1 FROM link_edges WHERE from_key = ?
              UNION ALL
              SELECT e.to_key, r.d + 1 FROM link_edges e
              JOIN reachable r ON e.from_key = r.k
              WHERE r.d < ?
            )
            SELECT DISTINCT k FROM reachable
          SQL
          @db.execute(sql, [key, depth]).map { |r| r["k"] }
        else
          sql = <<~SQL
            WITH RECURSIVE reachable(k) AS (
              SELECT to_key FROM link_edges WHERE from_key = ?
              UNION ALL
              SELECT e.to_key FROM link_edges e
              JOIN reachable r ON e.from_key = r.k
            )
            SELECT DISTINCT k FROM reachable
          SQL
          @db.execute(sql, [key]).map { |r| r["k"] }
        end
      end
    end
  end
end
