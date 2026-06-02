module Textus
  class Manifest
    class Entry
      module Publish
        # ADR 0049: the one walk->publish->prune pipeline shared by EachDir
        # (per-leaf subtree, ADR 0046) and Tree (whole-entry mirror, ADR 0047).
        # The two used to be near-duplicate methods (publish_subtree +
        # publish_tree_via, prune_orphans + prune_tree); their only real
        # difference — whether the prune honors the entry's `ignore` — is now the
        # explicit `prune_honors_ignore:` parameter.
        class SubtreeMirror
          def initialize(entry, pctx)
            @entry = entry
            @pctx  = pctx
          end

          # base:       store dir the entry owns — the root `ignored?` globs are
          #             relative to (ADR 0042).
          # walk_root:  dir the glob is rooted at (a single leaf dir for EachDir,
          #             == base for Tree). dst paths mirror rel-to-walk_root.
          # target_dir: repo-side destination root.
          # key/envelope: emitted per file; envelope is nil for the keyless Tree.
          # prune_honors_ignore: when true a managed file the entry `ignore`s
          #   survives the prune (ADR 0047 D4 — lets a derived index live in the
          #   mirrored dir); when false every unwritten managed file is pruned.
          def mirror(base:, walk_root:, target_dir:, key:, envelope:, prune_honors_ignore:)
            return { written: [], pruned: [] } unless File.directory?(walk_root)

            written = publish_files(base: base, walk_root: walk_root, target_dir: target_dir, key: key, envelope: envelope)
            { written: written, pruned: prune(target_dir, written, prune_honors_ignore) }
          end

          private

          def publish_files(base:, walk_root:, target_dir:, key:, envelope:)
            # FNM_DOTMATCH includes dotfiles; File.file? below skips dirs (and
            # symlinks-to-dirs). Trees are authored content, not symlink graphs.
            Dir.glob(File.join(walk_root, "**", "*"), File::FNM_DOTMATCH).sort.filter_map do |src|
              next nil unless File.file?(src)
              next nil if @entry.ignored?(relative(src, base))

              dst = File.join(target_dir, relative(src, walk_root))
              Textus::Ports::Publisher.publish(source: src, target: dst, store_root: @pctx.root)
              @pctx.emit(:file_published, key: key, envelope: envelope, source: src, target: dst)
              { "key" => key, "source" => src, "target" => dst }
            end
          end

          # Scoped to target_dir. Safe across leaves because ADR 0046 D5
          # (shallowest-index-wins) keeps leaf target dirs non-nesting, so
          # targets_under can't reach another leaf's sentinels.
          def prune(target_dir, written, honor_ignore)
            kept = written.map { |w| File.expand_path(w["target"]) }
            store = Textus::Ports::SentinelStore.new
            store.targets_under(target_dir, @pctx.root).filter_map do |managed|
              abs = File.expand_path(managed)
              next nil if kept.include?(abs)
              next nil if honor_ignore && @entry.ignored?(relative(abs, target_dir))

              Textus::Ports::Publisher.unpublish(target: managed, store_root: @pctx.root)
              managed
            end
          end

          def relative(path, root)
            path.sub(%r{\A#{Regexp.escape(root)}/}, "")
          end
        end
      end
    end
  end
end
