module Textus
  class Manifest
    class Entry
      # Pure glob matcher backing per-entry `ignore:` patterns (ADR 0042).
      # `rel_path` is the slash-joined path of a candidate file relative to the
      # entry's base directory.
      #
      # Matching is segment-wise so the `**` globstar means "zero or more path
      # segments" — `File.fnmatch` alone cannot express this (under
      # FNM_PATHNAME a trailing `**` will not cross a `/`; without it a leading
      # `**/` will not match zero leading segments). So `**/node_modules/**`
      # catches the `node_modules` subtree at any depth, including the store
      # root, and the directory entry itself.
      #
      # Within a single segment, matching delegates to `File.fnmatch` with
      # FNM_EXTGLOB, so a single `*` is anchored to that segment (it does not
      # cross `/`) and `{a,b}` alternation works.
      module IgnoreMatcher
        SEGMENT_FLAGS = File::FNM_EXTGLOB

        def self.match?(patterns, rel_path)
          path_segs = rel_path.split("/").reject(&:empty?)
          Array(patterns).any? do |pat|
            match_segments(pat.split("/").reject(&:empty?), path_segs)
          end
        end

        # Classic globstar matcher. `**` matches zero or more whole segments;
        # any other pattern segment matches exactly one path segment via fnmatch.
        def self.match_segments(pat_segs, path_segs)
          return path_segs.empty? if pat_segs.empty?

          if pat_segs.first == "**"
            match_segments(pat_segs[1..], path_segs) ||
              (!path_segs.empty? && match_segments(pat_segs, path_segs[1..]))
          else
            !path_segs.empty? &&
              File.fnmatch?(pat_segs.first, path_segs.first, SEGMENT_FLAGS) &&
              match_segments(pat_segs[1..], path_segs[1..])
          end
        end
        private_class_method :match_segments
      end
    end
  end
end
