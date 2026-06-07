module Textus
  class Manifest
    class Entry
      module Publish
        # publish.to: render or copy the entry's stored data to each fixed repo path.
        # The behaviour of any entry that declares `publish: [{ to: ... }, ...]`.
        # ADR 0094: iterates publish_targets (to-targets), rendering through a
        # template when the target declares one, or copying verbatim otherwise.
        class ToPaths < Mode
          def publish(pctx, prefix: nil) # rubocop:disable Lint/UnusedMethodArgument,Metrics/AbcSize
            targets = entry.publish_targets.select(&:to_target?)
            return nil if targets.empty?

            data_path = pctx.manifest.resolver.resolve(entry.key).path
            envelope  = pctx.reader.call(entry.key)
            renderer  = Textus::Write::PublishRenderer.new(template_loader: ->(n) { pctx.read_template(n) })
            content = nil # parsed lazily; the data's `content` (always _meta-free)

            targets.each do |t|
              content ||= Textus::Entry.for_format(entry.format).parse(File.read(data_path), path: data_path)["content"]
              src =
                if t.renders?
                  write_render(t, content, renderer, pctx, data_path)
                else
                  verbatim_source(entry, content, data_path)
                end
              target_abs = File.join(pctx.repo_root, t.to)
              Textus::Ports::Publisher.publish(source: src, target: target_abs, store_root: pctx.root)
              pctx.emit(:entry_published, key: entry.key, envelope: envelope, source: src, target: target_abs)
            end

            { kind: :built, value: { "key" => entry.key, "path" => data_path, "published_to" => targets.map(&:to) } }
          end

          private

          # Render to a temp file beside the data artifact so Publisher's
          # copy+sentinel primitive is unchanged.
          def write_render(target, content, renderer, pctx, data_path)
            boot  = target.inject_boot ? Textus::Boot.build(container: pctx.container) : nil
            bytes = renderer.bytes_for(target: target, data: content, boot: boot)
            tmp   = "#{data_path}.#{File.basename(target.to)}.rendered"
            File.binwrite(tmp, bytes)
            tmp
          end

          # ADR 0094: published artifacts are clean content — textus's `_meta`
          # stays in the store, never the consumer file. For a structured data
          # format, re-serialize the `content` (without `_meta`); for any other
          # format the stored file IS the content, so copy it verbatim.
          def verbatim_source(entry, content, data_path)
            return data_path unless %w[json yaml].include?(entry.format.to_s)

            bytes = Textus::Entry.for_format(entry.format).serialize(meta: {}, body: "", content: content)
            tmp   = "#{data_path}.clean.published"
            File.binwrite(tmp, bytes)
            tmp
          end
        end
      end
    end
  end
end
