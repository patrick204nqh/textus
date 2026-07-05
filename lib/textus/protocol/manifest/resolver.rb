module Textus
  module Protocol
    class Manifest
      class Resolver
        Resolution = ::Data.define(:entry, :path, :remaining)

        MAX_DISTANCE_LEN = 200

        def initialize(data)
          @data = data
        end

        def resolve(key)
          @data.validate_key!(key)
          dr = Protocol::Key.resolve(key, @data.entries)
          raise UnknownKey.new(key, suggestions: suggestions_for(key)) unless dr
          raise UnknownKey.new(key, suggestions: suggestions_for(key)) unless dr.entry

          Resolution.new(entry: dr.entry, path: build_path(dr.entry, dr.remaining), remaining: dr.remaining)
        end

        def suggestions_for(key)
          candidates = enumerate.map { |r| r[:key] }
          candidates.concat(@data.entries.reject { |e| nested_entry?(e) }.map(&:key))
          candidates.uniq!
          suggest(key, candidates, limit: 5)
        rescue StandardError
          []
        end

        def enumerate(prefix: nil, include_keyless: false)
          out = @data.entries.flat_map do |entry|
            nested_entry?(entry) ? enumerate_nested(entry, include_keyless: include_keyless) : enumerate_leaf(entry)
          end
          out.select! { |row| row[:key] == prefix || row[:key].start_with?("#{prefix}.") } if prefix
          out.sort_by { |row| row[:key] }
        end

        private

        def self.shared_prefix_segments(left, right)
          asegs = left.split(".")
          bsegs = right.split(".")
          n = [asegs.length, bsegs.length].min
          i = 0
          i += 1 while i < n && asegs[i] == bsegs[i]
          i
        end

        def self.levenshtein(left, right)
          return nil if left.length > MAX_DISTANCE_LEN || right.length > MAX_DISTANCE_LEN
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

        def suggest(requested, candidates, limit: 5)
          return [] if requested.nil? || requested.empty?

          scored = candidates.first(200).map do |k|
            prefix = self.class.shared_prefix_segments(requested, k)
            dist = self.class.levenshtein(requested, k) || Float::INFINITY
            [k, prefix, dist]
          end
          scored.sort_by { |(_, prefix, dist)| [-prefix, dist] }.first(limit).map(&:first)
        end

        def nested_entry?(entry)
          entry.nested?
        end

        def build_path(entry, remaining)
          if remaining.empty?
            resolve_leaf_path(entry)
          else
            primary_ext = Textus::Protocol::Format.for(entry.format).extensions.first
            base = Textus::Protocol::Key::Path.normalize_relative_path(entry.path)
            File.join(@data.root, base, *remaining) + primary_ext
          end
        end

        def enumerate_leaf(entry)
          fp = resolve_leaf_path(entry)
          File.exist?(fp) ? [{ key: entry.key, path: fp, manifest_entry: entry }] : []
        end

        def enumerate_nested(entry, include_keyless: false)
          # publish_tree mirrors opaque payload by path — its files are never
          # enumerated as keys (ADR 0047). Ask the resolved mode, not the path.
          # The `include_keyless:` override is used only by the projection lister
          # so that `from: project` selects can read source data from keyless
          # nested entries (e.g. knowledge.evidence) without exposing them as
          # addressable store keys in the public `list` surface.
          return [] if entry.publish_mode.keyless? && !include_keyless

          base = File.join(@data.root, Textus::Protocol::Key::Path.normalize_relative_path(entry.path))
          return [] unless File.directory?(base)

          Dir.glob(File.join(base, nested_glob(entry.format)))
             .filter_map { |path| nested_row_for(entry, base, path) }
        end

        def nested_row_for(entry, base, path)
          rel = path.sub(%r{\A#{Regexp.escape(base)}/?}, "")

          stripped = rel.sub(/#{Regexp.escape(File.extname(rel))}\z/, "")
          segs = stripped.split("/").reject { |s| s.empty? || s == "." }
          return nil if segs.empty?

          illegal = segs.find { |s| !valid_segment?(s) }
          if illegal
            warn("textus: skipping illegal key segment '#{illegal}' at #{path} — " \
                 "rename to match [a-z0-9][a-z0-9-]* (run 'textus doctor' for the full list)")
            return nil
          end

          { key: (entry.key.split(".") + segs).join("."), path: path, manifest_entry: entry }
        end

        def valid_segment?(seg)
          return false if seg.nil? || seg.empty?
          return false if seg.length > Protocol::Key::Grammar::MAX_SEGMENT_LEN

          seg.match?(Protocol::Key::Grammar::SEGMENT)
        end

        def resolve_leaf_path(entry)
          Textus::Protocol::Key::Path.resolve(@data, entry)
        end

        def nested_glob(format)
          Textus::Protocol::Format.for(format).nested_glob
        end
      end
    end
  end
end
