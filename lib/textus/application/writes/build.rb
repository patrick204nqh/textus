require "fileutils"

module Textus
  module Application
    module Writes
      # Materializes generator-zone entries (template + projection) onto disk
      # and copies the result to any configured `publish_to:` targets. Fires
      # `:build_completed` and `:file_published` events.
      #
      # For `publish_each:` (per-leaf publishing of nested entries), see
      # `Application::Writes::Publish`. The CLI verb `textus build` calls
      # both classes and merges the results.
      class Build
        def initialize(ctx:, manifest:, file_store:, bus:, root:, store:, hook_context:) # rubocop:disable Metrics/ParameterLists
          @ctx          = ctx
          @manifest     = manifest
          @file_store   = file_store
          @bus          = bus
          @root         = root
          @store        = store
          @hook_context = hook_context
        end

        def call(prefix: nil)
          built = @manifest.entries.filter_map do |mentry|
            next unless mentry.is_a?(Textus::Manifest::Entry::Derived)
            next unless mentry.in_generator_zone?
            next if prefix && !mentry.key.start_with?(prefix)

            materialize(mentry)
          end
          { "protocol" => Textus::PROTOCOL, "built" => built }
        end

        private

        def materialize(mentry)
          target_path = Materializer.new(
            ctx: @ctx, manifest: @manifest, file_store: @file_store,
            bus: @bus, root: @root, store: @store
          ).run(mentry)
          publish_and_fire(mentry, target_path)
          { "key" => mentry.key, "path" => target_path, "published_to" => mentry.publish_to }
        end

        def publish_and_fire(mentry, target_path)
          envelope = Textus::Application::Reads::Get.new(
            ctx: @ctx, manifest: @manifest, file_store: @file_store,
          ).call(mentry.key)
          repo_root = File.dirname(@root)

          mentry.publish_to.each do |rel|
            target_abs = File.join(repo_root, rel)
            Textus::Infra::Publisher.publish(source: target_path, target: target_abs, store_root: @root)
            publish_event(:file_published,
                          key: mentry.key,
                          envelope: envelope,
                          source: target_path,
                          target: target_abs)
          end

          src = mentry.source
          selects = src.is_a?(Textus::Manifest::Entry::Derived::Projection) ? Array(src.select).compact : []
          publish_event(:build_completed,
                        key: mentry.key,
                        envelope: envelope,
                        sources: selects)
        end

        def publish_event(event, **payload)
          @bus.publish(event, ctx: @hook_context, **payload)
        end
      end
    end
  end
end
