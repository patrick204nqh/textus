module Textus
  class Manifest
    class Entry
      module Publish
        # Base for every publish mode: wraps the resolved entry and owns the one
        # repo-root escape guard the writing modes share (ADR 0049). Subclasses
        # implement `#publish(pctx, prefix:)` returning the existing
        # `{ kind:, value:, pruned: }` shape (or nil), and `#validate!` for the
        # per-mode shape rules reached *because* this mode resolved.
        class Mode
          def initialize(entry)
            @entry = entry
          end

          attr_reader :entry

          # No shape rules by default — ToPaths/None publish without templating.
          def validate!; end

          # Whether this entry's subtree files are opaque payload that must
          # never be enumerated as keys. Only Tree (publish_tree, ADR 0047)
          # overrides to true; doctor's IllegalKeys and the resolver consult
          # this so they stop key-walking a keyless mirror's files.
          def keyless? = false

          private

          # Expand `rel` under repo_root and confirm it stays inside it.
          def repo_abs(pctx, rel)
            File.expand_path(File.join(pctx.repo_root, rel))
          end

          def inside_repo?(pctx, abs)
            abs.start_with?(File.expand_path(pctx.repo_root) + File::SEPARATOR)
          end

          # Store-side directory this entry's tree lives under.
          def store_base(pctx)
            File.join(pctx.root, "data", entry.path)
          end
        end
      end
    end
  end
end
