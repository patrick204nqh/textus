module Textus
  module Diff
    module_function

    def body(a_text, b_text)
      a_lines = (a_text || "").lines.map(&:chomp)
      b_lines = (b_text || "").lines.map(&:chomp)
      hunks = build_hunks(myers_diff(a_lines, b_lines), a_lines, b_lines)
      { "type" => "body", "hunks" => hunks, "stats" => stats(hunks) }
    end

    def meta(a_hash, b_hash)
      a = a_hash || {}
      b = b_hash || {}
      all_keys = (a.keys + b.keys).uniq.sort
      changes = all_keys.filter_map do |k|
        av = a[k]
        bv = b[k]
        next if av == bv

        { "key" => k.to_s, "old" => av, "new" => bv }
      end
      { "type" => "meta", "changes" => changes, "stats" => { "changed" => changes.size } }
    end

    def schema(a_schema, b_schema)
      meta(a_schema, b_schema).merge("type" => "schema")
    end

    def summary(diff_result)
      parts = []
      parts << "#{diff_result.dig("body", "stats", "additions") || 0}+" if diff_result["body"]
      parts << "#{diff_result.dig("body", "stats", "deletions") || 0}-" if diff_result["body"]
      parts << "#{diff_result.dig("meta", "stats", "changed") || 0}~" if diff_result["meta"]
      parts.join(" ")
    end

    # Myers diff algorithm — returns edit script as array of [:eq|:ins|:del, a_line, b_line]
    def myers_diff(a, b)
      n = a.size
      m = b.size
      max_d = n + m
      v = Hash.new(0)
      v[1] = 0
      trace = []

      (0..max_d).each do |d|
        (-d..d).step(2).each do |k|
          x = if k == -d || (k != d && v[k - 1] < v[k + 1])
                v[k + 1]
              else
                v[k - 1] + 1
              end
          y = x - k
          while x < n && y < m && a[x] == b[y]
            x += 1
            y += 1
          end
          v[k] = x
          return backtrack(trace, a, b, n, m) if x >= n && y >= m
        end
        trace << v.dup
      end
      []
    end

    def backtrack(trace, _a, _b, x, y)
      script = []
      d = trace.size - 1
      return script if d.negative?

      k = x - y
      while d.positive?
        prev_v = trace[d - 1]
        prev_k = if k == -d || (k != d && (prev_v[k - 1] || -1) < (prev_v[k + 1] || -1))
                   k + 1
                 else
                   k - 1
                 end
        prev_x = prev_v[prev_k] || 0
        prev_y = prev_x - prev_k

        while x > prev_x && y > prev_y
          script.unshift([:eq, x - 1, y - 1])
          x -= 1
          y -= 1
        end

        if x > prev_x
          script.unshift([:del, x - 1, nil])
          x -= 1
        elsif y > prev_y
          script.unshift([:ins, nil, y - 1])
          y -= 1
        end

        d -= 1
        k = prev_k
        x = prev_x
        y = prev_y
      end

      script
    end

    def build_hunks(script, a_lines, b_lines)
      return [] if script.empty?

      hunks = []
      i = 0
      while i < script.size
        next_context = find_next_change(script, i)
        break unless next_context

        start = [next_context - 3, 0].max
        hunk_end_script = find_hunk_end(script, next_context)
        hunk_end = [hunk_end_script + 3, script.size - 1].min

        a_start = nil
        b_start = nil
        a_lines_hunk = []
        b_lines_hunk = []

        (start..hunk_end).each do |j|
          op, ai, bi = script[j]
          a_start ||= ai if ai
          b_start ||= bi if bi

          case op
          when :eq
            a_lines_hunk << { "type" => "context", "line" => a_lines[ai] }
            b_lines_hunk << { "type" => "context", "line" => b_lines[bi] }
          when :del
            a_lines_hunk << { "type" => "deletion", "line" => a_lines[ai] }
          when :ins
            b_lines_hunk << { "type" => "addition", "line" => b_lines[bi] }
          end
        end

        hunks << {
          "a_start" => a_start, "b_start" => b_start,
          "a_lines" => a_lines_hunk, "b_lines" => b_lines_hunk
        }

        i = hunk_end + 1
      end

      hunks
    end

    def find_next_change(script, from)
      (from...script.size).find { |i| script[i][0] != :eq }
    end

    def find_hunk_end(script, from)
      last_change = from
      (from...[script.size, from + 6].min).each do |i|
        last_change = i if script[i][0] != :eq
      end
      last_change
    end

    def stats(hunks)
      additions = hunks.sum { |h| h["b_lines"].count { |l| l["type"] == "addition" } }
      deletions = hunks.sum { |h| h["a_lines"].count { |l| l["type"] == "deletion" } }
      { "additions" => additions, "deletions" => deletions, "hunks" => hunks.size }
    end
  end
end
