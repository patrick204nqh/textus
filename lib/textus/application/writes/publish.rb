module Textus
  module Application
    module Writes
      # Copies nested-leaf entries to their `publish_each:` targets. Fires
      # `:file_published` for each copy. Mirror of `Build` for the publish
      # half — split out from the old Build per ADR 0007.
      class Publish
        def initialize(ctx:)
          @ctx = ctx
        end

        def call(prefix: nil)
          repo_root = File.dirname(store.root)
          out = []
          manifest.entries.each do |mentry|
            next unless mentry.nested && mentry.publish_each
            next if prefix && !mentry.key.start_with?(prefix) && !prefix.start_with?("#{mentry.key}.")

            manifest.enumerate(prefix: mentry.key).each do |row|
              next unless row[:manifest_entry].equal?(mentry)
              next if prefix && !row[:key].start_with?(prefix) && row[:key] != prefix

              out << publish_leaf(mentry, row, repo_root)
            end
          end
          { "protocol" => Textus::PROTOCOL, "published_leaves" => out }
        end

        private

        def store = @ctx.store
        def manifest = store.manifest

        def publish_leaf(mentry, row, repo_root)
          target_rel = mentry.publish_target_for(row[:key])
          target_abs = File.expand_path(File.join(repo_root, target_rel))
          unless target_abs.start_with?(File.expand_path(repo_root) + File::SEPARATOR)
            raise PublishError.new(
              "entry '#{mentry.key}': publish_each target '#{target_rel}' for key '#{row[:key]}' escapes repo root",
            )
          end

          Textus::Infra::Publisher.publish(source: row[:path], target: target_abs, store_root: store.root)
          @ctx.bus.publish(:file_published,
                           store: @ctx.with_role(@ctx.role),
                           key: row[:key],
                           envelope: store.reader.get(row[:key]),
                           source: row[:path],
                           target: target_abs,
                           correlation_id: @ctx.correlation_id)
          { "key" => row[:key], "source" => row[:path], "target" => target_abs }
        end
      end
    end
  end
end
