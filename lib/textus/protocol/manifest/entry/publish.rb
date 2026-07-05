require "tempfile"

module Textus
  module Protocol
    class Manifest
      class Entry
        module Publish
          def self.resolve(entry)
            set = []
            set << "publish.to"   unless Array(entry.publish_to).empty?
            set << "publish.tree" unless entry.publish_tree.nil?

            if set.length > 1
              raise Textus::UsageError.new(
                "entry '#{entry.key}': #{set.join(" and ")} are mutually exclusive — an entry publishes exactly one way",
              )
            end

            mode_for(entry, set.first)
          end

          def self.mode_for(entry, key)
            case key
            when "publish.to"   then ToPaths.new(entry)
            when "publish.tree" then Tree.new(entry)
            else None.new(entry)
            end
          end
          private_class_method :mode_for

          class Mode
            def initialize(entry)
              @entry = entry
            end

            attr_reader :entry

            def validate!; end

            def keyless? = false

            private

            def repo_abs(pctx, rel)
              File.expand_path(File.join(pctx.repo_root, rel))
            end

            def inside_repo?(pctx, abs)
              abs.start_with?(File.expand_path(pctx.repo_root) + File::SEPARATOR)
            end

            def store_base(pctx)
              File.join(pctx.root, Textus::Protocol::Key::Path.normalize_relative_path(entry.path))
            end
          end

          class None < Mode
            def publish(_pctx, prefix: nil) = nil
          end

          # publish.to: render or copy the entry's stored data to each fixed repo path.
          class ToPaths < Mode
            def initialize(entry, publisher: Textus::Infra::Port::Publisher.new)
              super(entry)
              @publisher = publisher
            end

            def publish(pctx, prefix: nil)
              targets = entry.publish_targets.select(&:to_target?)
              return nil if targets.empty?

              data_path = pctx.manifest.resolver.resolve(entry.key).path
              envelope  = pctx.reader.call(key: entry.key)
              content = nil

              targets.each do |t|
                if t.renders?
                  content ||= Textus::Protocol::Format.for(entry.format).parse(File.read(data_path), path: data_path)["content"]
                  publish_bytes(render_bytes(t, content, pctx), entry.key, t, pctx, data_path, envelope)
                elsif strip_meta?(entry)
                  content ||= Textus::Protocol::Format.for(entry.format).parse(File.read(data_path), path: data_path)["content"]
                  bytes = Textus::Protocol::Format.for(entry.format).serialize(meta: {}, body: "", content: content)
                  publish_bytes(bytes, entry.key, t, pctx, data_path, envelope)
                else
                  target_abs = File.join(pctx.repo_root, t.to)
                  @publisher.publish(source: data_path, target: target_abs, store_root: pctx.root)
                  pctx.emit(:entry_published, key: entry.key, envelope: envelope, source: data_path, target: target_abs)
                end
              end

              { kind: :built, value: { "key" => entry.key, "path" => data_path, "published_to" => targets.map(&:to) } }
            end

            private

            def strip_meta?(entry)
              %w[json yaml].include?(entry.format.to_s)
            end

            def render_bytes(target, content, pctx)
              boot     = target.inject_boot ? Textus::Protocol::Boot.build(container: pctx.container) : nil
              renderer = Textus::Protocol::Produce::Render.new(
                template_loader: ->(n) { pctx.read_template(n) },
                manifest: pctx.manifest,
                source_publish_path: target.to,
                entry_key: entry.key,
                edge_store: pctx.container.store.link_store,
              )
              renderer.bytes_for(target: target, data: content, boot: boot)
            end

            def publish_bytes(bytes, key, target, pctx, data_path, envelope)
              target_abs = File.join(pctx.repo_root, target.to)
              Tempfile.create(["textus-publish", File.extname(target.to)]) do |f|
                f.binmode
                f.write(bytes)
                f.flush
                @publisher.publish(
                  source: f.path, target: target_abs, store_root: pctx.root, provenance_source: data_path,
                )
              end
              pctx.emit(:entry_published, key: key, envelope: envelope, source: data_path, target: target_abs)
            end
          end

          # publish.tree: mirror this entry's whole subtree to one target dir.
          class Tree < Mode
            def keyless? = true

            def publish(pctx, prefix: nil)
              target_rel = entry.publish_tree
              target_dir = repo_abs(pctx, target_rel)
              unless inside_repo?(pctx, target_dir)
                raise Textus::PublishError.new(
                  "entry '#{entry.key}': publish_tree target '#{target_rel}' escapes repo root",
                )
              end

              result = SubtreeMirror.new(entry, pctx).mirror(
                walk_root: store_base(pctx),
                target_dir: target_dir,
                key: entry.key,
                envelope: nil,
              )
              { kind: :leaves, value: result[:written], pruned: result[:pruned] }
            end

            def validate!
              publish_tree = entry.publish_tree
              raise UsageError.new("entry '#{entry.key}': publish.tree must be a string") unless publish_tree.is_a?(String)

              used_vars = publish_tree.scan(/\{([a-z]+)\}/).flatten
              return if used_vars.empty?

              raise UsageError.new(
                "entry '#{entry.key}': publish.tree names a single directory and takes no template variable(s) " \
                "#{used_vars.map { |v| "{#{v}}" }.join(", ")} — it mirrors the whole subtree to one target dir.",
              )
            end
          end

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
end
