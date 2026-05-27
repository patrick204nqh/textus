module Textus
  class Manifest
    class Resolver
      def initialize(manifest)
        @manifest = manifest
      end

      def resolve(key)
        @manifest.validate_key!(key)
        segments = key.split(".")
        candidates = @manifest.entries
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
        candidates.concat(@manifest.entries.reject(&:nested).map(&:key))
        candidates.uniq!
        Key::Distance.suggest(key, candidates, limit: 5)
      rescue StandardError
        []
      end

      def enumerate(prefix: nil)
        out = @manifest.entries.flat_map { |entry| entry.nested ? enumerate_nested(entry) : enumerate_leaf(entry) }
        out.select! { |row| row[:key] == prefix || row[:key].start_with?("#{prefix}.") } if prefix
        out.sort_by { |row| row[:key] }
      end

      private

      def build_resolution(entry, remaining, key)
        if remaining.empty?
          Resolution.new(entry: entry, path: resolve_leaf_path(entry), remaining: [])
        else
          raise UnknownKey.new(key, suggestions: suggestions_for(key)) unless entry.nested

          path = if entry.index_filename
                   File.join(@manifest.root, "zones", entry.path, *remaining, entry.index_filename)
                 else
                   primary_ext = Textus::Entry.for_format(entry.format).extensions.first
                   File.join(@manifest.root, "zones", entry.path, *remaining) + primary_ext
                 end
          Resolution.new(entry: entry, path: path, remaining: remaining)
        end
      end

      def enumerate_leaf(entry)
        fp = resolve_leaf_path(entry)
        File.exist?(fp) ? [{ key: entry.key, path: fp, manifest_entry: entry }] : []
      end

      def enumerate_nested(entry)
        base = File.join(@manifest.root, "zones", entry.path)
        return [] unless File.directory?(base)

        glob_pattern = entry.index_filename ? "**/#{entry.index_filename}" : nested_glob(entry.format)
        Dir.glob(File.join(base, glob_pattern)).filter_map { |path| nested_row_for(entry, base, path) }
      end

      def nested_row_for(entry, base, path)
        rel = path.sub(%r{\A#{Regexp.escape(base)}/?}, "")
        stripped = entry.index_filename ? File.dirname(rel) : rel.sub(/#{Regexp.escape(File.extname(rel))}\z/, "")
        segs = stripped.split("/").reject { |s| s.empty? || s == "." }
        return nil if segs.empty?

        illegal = segs.find { |s| !valid_segment?(s) }
        if illegal
          warn("textus: skipping illegal key segment '#{illegal}' at #{path} — run 'textus key normalize --dry-run'")
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
        Textus::Key::Path.resolve(@manifest, entry)
      end

      def nested_glob(format)
        Textus::Entry.for_format(format).nested_glob
      end
    end
  end
end
