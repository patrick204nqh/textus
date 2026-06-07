module Textus
  class Manifest
    class Entry
      module Publish
        # publish.to: render or copy the entry's stored data to each fixed repo path.
        # The behaviour of any entry that declares `publish: [{ to: ... }, ...]`.
        # ADR 0094: iterates publish_targets (to-targets), rendering through a
        # template when the target declares one, or copying verbatim otherwise.
        class ToPaths < Mode
          def publish(pctx, prefix: nil) # rubocop:disable Lint/UnusedMethodArgument
            targets = entry.publish_targets.select(&:to_target?)
            return nil if targets.empty?

            data_path = pctx.manifest.resolver.resolve(entry.key).path
            envelope  = pctx.reader.call(entry.key)
            renderer  = Textus::Write::PublishRenderer.new(template_loader: ->(n) { pctx.read_template(n) })
            data      = nil # parsed lazily, only if a target renders

            targets.each do |t|
              src =
                if t.renders?
                  data ||= Textus::Entry.for_format(entry.format).parse(File.read(data_path), path: data_path)["content"]
                  write_render(t, data, renderer, pctx, data_path)
                else
                  data_path
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
          def write_render(target, data, renderer, pctx, data_path)
            boot  = target.inject_boot ? Textus::Boot.build(container: pctx.container) : nil
            bytes = renderer.bytes_for(target: target, data: data, boot: boot)
            tmp   = "#{data_path}.#{File.basename(target.to)}.rendered"
            File.binwrite(tmp, bytes)
            tmp
          end
        end
      end
    end
  end
end
