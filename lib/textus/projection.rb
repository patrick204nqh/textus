require "time"
require "timeout"

module Textus
  class Projection
    MAX_LIMIT = 1000
    REDUCER_TIMEOUT_SECONDS = 2

    # `reader` — a callable `->(key) { envelope_or_nil }`. Caller picks
    #   semantics: pure read (`ops.get`) for materialization paths;
    #   `ops.get_or_refresh` if you want refresh-on-stale.
    # `lister` — a callable `->(prefix:) { [ { "key" => ... }, ... ] }`.
    # `rpc` — a `Hooks::RpcRegistry` used to dispatch `transform_rows` callables.
    # `transform_context` — capability object handed to transform reducers as `caps:`.
    def initialize(reader:, spec:, lister:, rpc:, transform_context:)
      @reader            = reader
      @spec              = spec || {}
      @lister            = lister
      @rpc               = rpc
      @transform_context = transform_context
      @limit = (@spec["limit"] || MAX_LIMIT).to_i
      raise InvalidProjection.new("limit #{@limit} exceeds max #{MAX_LIMIT}") if @limit > MAX_LIMIT
    end

    def run
      keys = collect_keys
      explicit_pluck = !@spec["pluck"].nil? && @spec["pluck"] != "*"
      rows = keys.map do |key|
        env = @reader.call(key)
        row = pluck(env.meta, env.body)
        explicit_pluck ? row : row.merge("_key" => key)
      end
      reduced = apply_reducer(rows)
      # Reducers may return either an Array of rows (legacy / templated builds)
      # or a Hash that becomes the structured-format payload base. In the Hash
      # case, downstream sort/limit/position markers don't apply, and the
      # builder owns `_meta.generated_at` so we don't stamp it here.
      return reduced if reduced.is_a?(Hash)

      rows = reduced
      rows = sort(rows)
      rows = rows.first(@limit)
      mark_positions(rows)
      { "entries" => rows, "count" => rows.length, "generated_at" => Time.now.utc.iso8601 }
    end

    private

    def apply_reducer(rows)
      name = @spec["transform"] or return rows
      Timeout.timeout(REDUCER_TIMEOUT_SECONDS) do
        @rpc.invoke(:transform_rows, name,
                    caps: @transform_context,
                    rows: rows,
                    config: @spec["transform_config"] || {})
      end
    rescue Timeout::Error
      raise UsageError.new("transform_rows '#{name}' exceeded #{REDUCER_TIMEOUT_SECONDS}s timeout")
    end

    def collect_keys
      prefixes = Array(@spec["select"])
      prefixes.flat_map { |p| @lister.call(prefix: p).map { |row| row["key"] } }.uniq
    end

    def pluck(frontmatter, _body)
      fields = @spec["pluck"]
      if fields.nil? || fields == "*"
        frontmatter
      else
        Array(fields).each_with_object({}) { |f, h| h[f] = frontmatter[f] if frontmatter.key?(f) }
      end
    end

    # Adds `_first`, `_last`, and `_index` markers so templates can emit
    # delimiters (e.g. JSON commas) via {{^_last}},{{/_last}}.
    def mark_positions(rows)
      last_idx = rows.length - 1
      rows.each_with_index do |row, i|
        row["_index"] = i
        row["_first"] = i.zero?
        row["_last"]  = (i == last_idx)
      end
    end

    def sort(rows)
      sb = @spec["sort_by"] or return rows
      rows.sort_by { |r| r[sb].to_s }
    end
  end
end
