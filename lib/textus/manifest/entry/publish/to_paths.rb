module Textus
  class Manifest
    class Entry
      module Publish
        # publish.to: copy the entry's one stored file to each fixed repo path.
        # The behaviour of any entry that declares `publish: { to: [...] }`.
        class ToPaths < Mode
          def publish(pctx, prefix: nil) # rubocop:disable Lint/UnusedMethodArgument
            targets = Array(entry.publish_to)
            return nil if targets.empty?

            source_path = pctx.manifest.resolver.resolve(entry.key).path
            envelope = pctx.reader.call(entry.key)

            targets.each do |rel|
              target_abs = File.join(pctx.repo_root, rel)
              Textus::Ports::Publisher.publish(source: source_path, target: target_abs, store_root: pctx.root)
              pctx.emit(:file_published, key: entry.key, envelope: envelope, source: source_path, target: target_abs)
            end

            { kind: :built, value: { "key" => entry.key, "path" => source_path, "published_to" => targets } }
          end
        end
      end
    end
  end
end
