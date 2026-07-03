module Textus
  module Protocol
    module Key
      class Distance
        MAX_LEN = 200

        def self.shared_prefix_segments(left, right)
          asegs = left.split(".")
          bsegs = right.split(".")
          n = [asegs.length, bsegs.length].min
          i = 0
          i += 1 while i < n && asegs[i] == bsegs[i]
          i
        end

        def self.levenshtein(left, right)
          return nil if left.length > MAX_LEN || right.length > MAX_LEN
          return right.length if left.empty?
          return left.length if right.empty?

          prev = (0..right.length).to_a
          curr = Array.new(right.length + 1, 0)
          (1..left.length).each do |i|
            curr[0] = i
            (1..right.length).each do |j|
              cost = left[i - 1] == right[j - 1] ? 0 : 1
              curr[j] = [
                curr[j - 1] + 1,
                prev[j] + 1,
                prev[j - 1] + cost,
              ].min
            end
            prev, curr = curr, prev
          end
          prev[right.length]
        end

        def self.suggest(requested, candidates, limit: 5)
          return [] if requested.nil? || requested.empty?

          scored = candidates.first(200).map do |k|
            prefix = shared_prefix_segments(requested, k)
            dist = levenshtein(requested, k) || Float::INFINITY
            [k, prefix, dist]
          end
          scored.sort_by { |(_, prefix, dist)| [-prefix, dist] }.first(limit).map(&:first)
        end
      end
    end
  end
end
