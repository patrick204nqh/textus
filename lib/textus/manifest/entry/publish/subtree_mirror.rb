module Textus
  class Manifest
    class Entry
      module Publish
        class SubtreeMirror
          def initialize(entry, pctx, publisher: Textus::Infra::Port::Publisher.new)
            @entry     = entry
            @pctx      = pctx
            @publisher = publisher
          end

          def mirror(walk_root:, target_dir:, key:, envelope:)
            return { written: [], pruned: [] } unless File.directory?(walk_root)

            written = publish_files(walk_root: walk_root, target_dir: target_dir, key: key, envelope: envelope)
            { written: written, pruned: prune(target_dir, written) }
          end

          private

          def publish_files(walk_root:, target_dir:, key:, envelope:)
            Dir.glob(File.join(walk_root, "**", "*"), File::FNM_DOTMATCH).sort.filter_map do |src|
              next nil unless File.file?(src)

              dst = File.join(target_dir, relative(src, walk_root))
              @publisher.publish(source: src, target: dst, store_root: @pctx.root)
              @pctx.emit(:entry_published, key: key, envelope: envelope, source: src, target: dst)
              { "key" => key, "source" => src, "target" => dst }
            end
          end

          def prune(target_dir, written)
            kept = written.map { |w| File.expand_path(w["target"]) }
            store = Textus::Infra::Port::SentinelStore.new
            store.targets_under(target_dir, @pctx.root).filter_map do |managed|
              abs = File.expand_path(managed)
              next nil if kept.include?(abs)

              @publisher.unpublish(target: managed, store_root: @pctx.root)
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
