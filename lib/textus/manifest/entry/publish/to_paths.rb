require "tempfile"

module Textus
  class Manifest
    class Entry
      module Publish
        # publish.to: render or copy the entry's stored data to each fixed repo path.
        # The behaviour of any entry that declares `publish: [{ to: ... }, ...]`.
        # ADR 0094: iterates publish_targets (to-targets), rendering through a
        # template when the target declares one, or copying verbatim otherwise.
        class ToPaths < Mode
          def initialize(entry, publisher: Textus::Port::Publisher.new)
            super(entry)
            @publisher = publisher
          end

          def publish(pctx, prefix: nil) # rubocop:disable Lint/UnusedMethodArgument
            targets = entry.publish_targets.select(&:to_target?)

            return nil if targets.empty?

            data_path = pctx.manifest.resolver.resolve(entry.key).path
            envelope  = pctx.reader.call(entry.key)
            renderer  = Textus::Produce::Render.new(template_loader: ->(n) { pctx.read_template(n) })
            content = nil # parsed lazily; the data's `content` (always _meta-free)

            targets.each do |t|
              if t.renders?
                content ||= Textus::Format.for(entry.format).parse(File.read(data_path), path: data_path)["content"]
                publish_bytes(render_bytes(t, content, renderer, pctx), entry.key, t, pctx, data_path, envelope)
              elsif strip_meta?(entry)
                content ||= Textus::Format.for(entry.format).parse(File.read(data_path), path: data_path)["content"]
                bytes = Textus::Format.for(entry.format).serialize(meta: {}, body: "", content: content)
                publish_bytes(bytes, entry.key, t, pctx, data_path, envelope)
              else
                # opaque / command / non-structured — publish the stored file as-is
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

          def render_bytes(target, content, renderer, pctx)
            boot = target.inject_boot ? Textus::Boot.build(container: pctx.container) : nil
            renderer.bytes_for(target: target, data: content, boot: boot)
          end

          # Write bytes to a system temp, publish (recording the persistent data
          # file as the sentinel source), then remove the temp — the store is
          # never polluted with render artifacts.
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
      end
    end
  end
end
