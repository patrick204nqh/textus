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
        def initialize(ctx:, manifest:, file_store:, bus:, root:, store:)
          @ctx        = ctx
          @manifest   = manifest
          @file_store = file_store
          @bus        = bus
          @root       = root
          # T11 will replace `store:` here when Builder::Pipeline takes
          # reader/lister callables instead of a store handle.
          @store      = store
        end

        def call(prefix: nil)
          built = @manifest.entries.filter_map do |mentry|
            next unless mentry.in_generator_zone?
            next unless mentry.projection || mentry.template
            next if prefix && !mentry.key.start_with?(prefix)

            materialize(mentry)
          end
          { "protocol" => Textus::PROTOCOL, "built" => built }
        end

        private

        def materialize(mentry)
          target_path = Builder::Pipeline.run(
            store: @store,
            mentry: mentry,
            template_loader: ->(name) { read_template(name) },
          )
          publish_and_fire(mentry, target_path)
          { "key" => mentry.key, "path" => target_path, "published_to" => mentry.publish_to }
        end

        def read_template(name)
          tpl_path = File.join(@root, "templates", name)
          raise TemplateError.new("template not found: #{tpl_path}", template_name: name) unless File.exist?(tpl_path)

          File.read(tpl_path)
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

          publish_event(:build_completed,
                        key: mentry.key,
                        envelope: envelope,
                        sources: Array(mentry.projection&.fetch("select", nil)).compact)
        end

        def publish_event(event, **payload)
          @bus.publish(event, store: @store, role: @ctx.role, correlation_id: @ctx.correlation_id, **payload)
        end
      end
    end
  end
end
