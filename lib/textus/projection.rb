require "time"
require "timeout"

module Textus
  class Projection
    MAX_LIMIT = 1000
    REDUCER_TIMEOUT_SECONDS = 2

    # `reader` — a callable `->(key) { envelope_or_nil }`. `Read::Get` is a pure
    #   read on every path (ADR 0089): it annotates freshness but never ingests,
    #   so materialization and any other reader share the same side-effect-free read.
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
      pluck_key = explicit_pluck && Array(@spec["pluck"]).include?("_key")
      rows = keys.map do |key|
        env = @reader.call(key)
        row = pluck(env.meta, env.body)
        if explicit_pluck
          pluck_key ? row.merge("_key" => key) : row
        else
          row.merge("_key" => key)
        end
      end
      reduced = apply_reducer(rows)
      # Reducers may return either an Array of rows (legacy / templated builds)
      # or a Hash that becomes the structured-format payload base. In the Hash
      # case, downstream sort/limit/position markers don't apply.
      return reduced if reduced.is_a?(Hash)

      rows = reduced
      rows = sort(rows)
      rows = rows.first(@limit)
      mark_positions(rows)
      # No `generated_at` in the payload — the built artifact is content-addressed
      # (ADR 0070); volatile build time is kept out of the tracked output.
      { "entries" => rows, "count" => rows.length }
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

    def pluck(frontmatter, body)
      fields = @spec["pluck"]
      if fields.nil? || fields == "*"
        frontmatter
      else
        Array(fields).each_with_object({}) do |f, h|
          if f == "body"
            h["body"] = body
          elsif frontmatter.key?(f)
            h[f] = frontmatter[f]
          end
        end
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
