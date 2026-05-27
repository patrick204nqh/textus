module Textus
  module Application
    module Writes
      # Copies nested-leaf entries to their `publish_each:` targets. Fires
      # `:file_published` for each copy. Mirror of `Build` for the publish
      # half — split out from the old Build per ADR 0007.
      class Publish
        def initialize(ctx:, manifest:, file_store:, bus:, root:, hook_context:)
          @ctx          = ctx
          @manifest     = manifest
          @file_store   = file_store
          @bus          = bus
          @root         = root
          @hook_context = hook_context
        end

        def call(prefix: nil)
          repo_root = File.dirname(@root)
          out = []
          @manifest.entries.each do |mentry|
            next unless mentry.nested && mentry.publish_each
            next if prefix && !mentry.key.start_with?(prefix) && !prefix.start_with?("#{mentry.key}.")

            @manifest.resolver.enumerate(prefix: mentry.key).each do |row|
              next unless row[:manifest_entry].equal?(mentry)
              next if prefix && !row[:key].start_with?(prefix) && row[:key] != prefix

              out << publish_leaf(mentry, row, repo_root)
            end
          end
          { "protocol" => Textus::PROTOCOL, "published_leaves" => out }
        end

        private

        def publish_leaf(mentry, row, repo_root)
          target_rel = mentry.publish_target_for(row[:key])
          target_abs = File.expand_path(File.join(repo_root, target_rel))
          unless target_abs.start_with?(File.expand_path(repo_root) + File::SEPARATOR)
            raise PublishError.new(
              "entry '#{mentry.key}': publish_each target '#{target_rel}' for key '#{row[:key]}' escapes repo root",
            )
          end

          Textus::Infra::Publisher.publish(source: row[:path], target: target_abs, store_root: @root)
          reader = Textus::Application::Reads::Get.new(
            ctx: @ctx, manifest: @manifest, file_store: @file_store,
          )
          @bus.publish(:file_published,
                       ctx: @hook_context,
                       key: row[:key],
                       envelope: reader.call(row[:key]),
                       source: row[:path],
                       target: target_abs)
          { "key" => row[:key], "source" => row[:path], "target" => target_abs }
        end
      end
    end
  end
end
