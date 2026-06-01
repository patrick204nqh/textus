module Textus
  class Manifest
    class Entry
      class Nested < Base
        PUBLISH_EACH_VARS   = Validators::PublishEach::KNOWN_VARS
        PUBLISH_EACH_VAR_RE = Validators::PublishEach::VAR_RE

        attr_reader :index_filename, :publish_each, :ignore

        def initialize(index_filename: nil, publish_each: nil, ignore: nil, **rest)
          super(**rest)
          @index_filename = index_filename
          @publish_each = publish_each
          @ignore = Array(ignore)
        end

        def nested? = true

        # True when `rel_path` (slash-joined, relative to the entry base) matches
        # any configured ignore glob. Evaluated ABOVE key-legality (ADR 0042):
        # an ignored path is excluded, never judged.
        def ignored?(rel_path) = IgnoreMatcher.match?(@ignore, rel_path)

        def publish_target_for(full_key)
          return nil if @publish_each.nil?

          entry_segs = @key.split(".")
          key_segs = full_key.split(".")
          raise UsageError.new("key '#{full_key}' is not under entry '#{@key}'") unless key_segs[0, entry_segs.length] == entry_segs

          remaining = key_segs[entry_segs.length..] || []
          leaf = remaining.join("/")
          basename = remaining.last || ""
          ext = Textus::Entry.for_format(@format).extensions.first.to_s.sub(/^\./, "")

          vars = { "leaf" => leaf, "basename" => basename, "key" => full_key, "ext" => ext }
          @publish_each.gsub(PUBLISH_EACH_VAR_RE) { vars.fetch(::Regexp.last_match(1)) }
        end

        def publish_via(pctx, prefix: nil)
          return nil if @publish_each.nil?

          leaves = []
          pruned = [] # accumulates orphans removed by prune_orphans below
          pctx.manifest.resolver.enumerate(prefix: @key).each do |row|
            next unless row[:manifest_entry].equal?(self)
            next if prefix && !row[:key].start_with?(prefix) && row[:key] != prefix

            target_rel = publish_target_for(row[:key])
            target_abs = File.expand_path(File.join(pctx.repo_root, target_rel))
            unless target_abs.start_with?(File.expand_path(pctx.repo_root) + File::SEPARATOR)
              raise Textus::PublishError.new(
                "entry '#{@key}': publish_each target '#{target_rel}' for key '#{row[:key]}' escapes repo root",
              )
            end

            written = @index_filename ? publish_subtree(row, target_abs, pctx) : [publish_one(row, target_abs, pctx)]
            pruned.concat(prune_orphans(target_abs, written, pctx)) if @index_filename
            written.each { |w| leaves << { "key" => row[:key], "source" => w["source"], "target" => w["target"] } }
          end

          { kind: :leaves, value: leaves, pruned: pruned }
        end

        def publish_one(row, target_abs, pctx)
          Textus::Ports::Publisher.publish(source: row[:path], target: target_abs, store_root: pctx.root)
          pctx.emit(:file_published, key: row[:key], envelope: pctx.reader.call(row[:key]),
                                     source: row[:path], target: target_abs)
          { "source" => row[:path], "target" => target_abs }
        end

        def publish_subtree(row, target_dir, pctx)
          base = File.join(pctx.root, "zones", path)
          leaf_dir = File.dirname(row[:path])
          # FNM_DOTMATCH includes dotfiles; File.file? below skips dirs (and symlinks-to-dirs). Leaf trees are authored content, not arbitrary symlink graphs.
          Dir.glob(File.join(leaf_dir, "**", "*"), File::FNM_DOTMATCH).sort.filter_map do |src|
            next nil unless File.file?(src)

            rel_to_base = src.sub(%r{\A#{Regexp.escape(base)}/}, "")
            next nil if ignored?(rel_to_base)

            rel_to_leaf = src.sub(%r{\A#{Regexp.escape(leaf_dir)}/}, "")
            dst = File.join(target_dir, rel_to_leaf)
            Textus::Ports::Publisher.publish(source: src, target: dst, store_root: pctx.root)
            pctx.emit(:file_published, key: row[:key], envelope: pctx.reader.call(row[:key]),
                                       source: src, target: dst)
            { "source" => src, "target" => dst }
          end
        end

        def prune_orphans(target_dir, written, pctx)
          kept = written.map { |w| File.expand_path(w["target"]) }
          store = Textus::Ports::SentinelStore.new
          store.targets_under(target_dir, pctx.root).filter_map do |managed|
            next nil if kept.include?(File.expand_path(managed))

            Textus::Ports::Publisher.unpublish(target: managed, store_root: pctx.root)
            managed
          end
        end

        # Helpers are private; KIND / self.from_raw / REGISTRY below are intentionally public.
        private :publish_one, :publish_subtree, :prune_orphans

        KIND = :nested

        def self.from_raw(common, raw)
          new(
            index_filename: raw["index_filename"],
            publish_each: raw["publish_each"],
            ignore: raw["ignore"],
            **common,
          )
        end

        Entry::REGISTRY[KIND] = self
      end
    end
  end
end
