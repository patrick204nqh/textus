require "time"

module Textus
  class Projection
    MAX_LIMIT = 1000

    def initialize(store, spec)
      @store = store
      @spec = spec || {}
      @limit = (@spec["limit"] || MAX_LIMIT).to_i
      raise InvalidProjection.new("limit #{@limit} exceeds max #{MAX_LIMIT}") if @limit > MAX_LIMIT
    end

    def run
      keys = collect_keys
      explicit_pluck = !@spec["pluck"].nil? && @spec["pluck"] != "*"
      rows = keys.map do |key|
        env = @store.get(key)
        row = pluck(env["frontmatter"], env["body"])
        explicit_pluck ? row : row.merge("_key" => key)
      end
      rows = sort(rows)
      rows = rows.first(@limit)
      { "entries" => rows, "count" => rows.length, "generated_at" => Time.now.utc.iso8601 }
    end

    private

    def collect_keys
      prefixes = Array(@spec["select"])
      prefixes.flat_map { |p| @store.list(prefix: p).map { |row| row["key"] } }.uniq
    end

    def pluck(frontmatter, _body)
      fields = @spec["pluck"]
      if fields.nil? || fields == "*"
        frontmatter
      else
        Array(fields).each_with_object({}) { |f, h| h[f] = frontmatter[f] if frontmatter.key?(f) }
      end
    end

    def sort(rows)
      sb = @spec["sort_by"] or return rows
      rows.sort_by { |r| r[sb].to_s }
    end
  end
end
