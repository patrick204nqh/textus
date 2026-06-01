module Textus
  class Manifest
    class Resolver
      Resolution = ::Data.define(:entry, :path, :remaining)

      def initialize(data)
        @data = data
      end

      def resolve(key)
        @data.validate_key!(key)
        segments = key.split(".")
        candidates = @data.entries
                          .map { |e| [e, e.key.split(".")] }
                          .select { |(_, esegs)| esegs == segments[0, esegs.length] }
                          .sort_by { |(_, esegs)| -esegs.length }
        raise UnknownKey.new(key, suggestions: suggestions_for(key)) if candidates.empty?

        entry, esegs = candidates.first
        remaining = segments[esegs.length..]
        build_resolution(entry, remaining, key)
      end

      def suggestions_for(key)
        candidates = enumerate.map { |r| r[:key] }
        candidates.concat(@data.entries.reject { |e| nested_entry?(e) }.map(&:key))
        candidates.uniq!
        Key::Distance.suggest(key, candidates, limit: 5)
      rescue StandardError
        []
      end

      def enumerate(prefix: nil)
        out = @data.entries.flat_map { |entry| nested_entry?(entry) ? enumerate_nested(entry) : enumerate_leaf(entry) }
        out.select! { |row| row[:key] == prefix || row[:key].start_with?("#{prefix}.") } if prefix
        out.sort_by { |row| row[:key] }
      end

      private

      # Returns true for entries that behave as nested (Nested subclass, or any
      # entry with nested: true in the raw YAML — e.g. Intake entries covering
      # a directory of leaf files).
      def nested_entry?(entry)
        entry.nested?
      end

      def build_resolution(entry, remaining, key)
        if remaining.empty?
          Resolution.new(entry: entry, path: resolve_leaf_path(entry), remaining: [])
        else
          raise UnknownKey.new(key, suggestions: suggestions_for(key)) unless nested_entry?(entry)

          index_fn = entry.index_filename
          path = if index_fn
                   File.join(@data.root, "zones", entry.path, *remaining, index_fn)
                 else
                   primary_ext = Textus::Entry.for_format(entry.format).extensions.first
                   File.join(@data.root, "zones", entry.path, *remaining) + primary_ext
                 end
          Resolution.new(entry: entry, path: path, remaining: remaining)
        end
      end

      def enumerate_leaf(entry)
        fp = resolve_leaf_path(entry)
        File.exist?(fp) ? [{ key: entry.key, path: fp, manifest_entry: entry }] : []
      end

      def enumerate_nested(entry)
        base = File.join(@data.root, "zones", entry.path)
        return [] unless File.directory?(base)

        entry_index_filename = entry.index_filename
        unless entry_index_filename
          return Dir.glob(File.join(base, nested_glob(entry.format)))
                    .filter_map { |path| nested_row_for(entry, base, path) }
        end

        claimed = []
        Dir.glob(File.join(base, "**", entry_index_filename))
           .sort_by { |path| path.count("/") }
           .filter_map do |path|
          leaf_dir = File.dirname(path)
          next nil if claimed.any? { |d| leaf_dir.start_with?("#{d}/") }

          claimed << leaf_dir
          nested_row_for(entry, base, path)
        end
      end

      def nested_row_for(entry, base, path)
        rel = path.sub(%r{\A#{Regexp.escape(base)}/?}, "")
        return nil if entry.ignored?(rel)

        entry_if = entry.index_filename
        stripped = entry_if ? File.dirname(rel) : rel.sub(/#{Regexp.escape(File.extname(rel))}\z/, "")
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
        return false if seg.length > Key::Grammar::MAX_SEGMENT_LEN

        seg.match?(Key::Grammar::SEGMENT)
      end

      def resolve_leaf_path(entry)
        Textus::Key::Path.resolve(@data, entry)
      end

      def nested_glob(format)
        Textus::Entry.for_format(format).nested_glob
      end
    end
  end
end
