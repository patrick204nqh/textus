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
        candidates.concat(@manifest.entries.reject { |e| nested_entry?(e) }.map(&:key))
        candidates.uniq!
        Key::Distance.suggest(key, candidates, limit: 5)
      rescue StandardError
        []
      end

      def enumerate(prefix: nil)
        out = @manifest.entries.flat_map { |entry| nested_entry?(entry) ? enumerate_nested(entry) : enumerate_leaf(entry) }
        out.select! { |row| row[:key] == prefix || row[:key].start_with?("#{prefix}.") } if prefix
        out.sort_by { |row| row[:key] }
      end

      private

      # Returns true for entries that behave as nested (Nested subclass, or any
      # entry with nested: true in the raw YAML — e.g. Intake entries covering
      # a directory of leaf files).
      def nested_entry?(entry)
        entry.is_a?(Textus::Manifest::Entry::Nested) || entry.raw["nested"] == true
      end

      def build_resolution(entry, remaining, key)
        if remaining.empty?
          Resolution.new(entry: entry, path: resolve_leaf_path(entry), remaining: [])
        else
          raise UnknownKey.new(key, suggestions: suggestions_for(key)) unless nested_entry?(entry)

          index_fn = entry.respond_to?(:index_filename) ? entry.index_filename : nil
          path = if index_fn
                   File.join(@manifest.root, "zones", entry.path, *remaining, index_fn)
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

        entry_index_filename = entry.respond_to?(:index_filename) ? entry.index_filename : nil
        glob_pattern = entry_index_filename ? "**/#{entry_index_filename}" : nested_glob(entry.format)
        Dir.glob(File.join(base, glob_pattern)).filter_map { |path| nested_row_for(entry, base, path) }
      end

      def nested_row_for(entry, base, path)
        rel = path.sub(%r{\A#{Regexp.escape(base)}/?}, "")
        entry_if = entry.respond_to?(:index_filename) ? entry.index_filename : nil
        stripped = entry_if ? File.dirname(rel) : rel.sub(/#{Regexp.escape(File.extname(rel))}\z/, "")
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
