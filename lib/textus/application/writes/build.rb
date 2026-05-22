require "fileutils"

module Textus
  module Application
    module Writes
      # Materializes generator-zone entries (template + projection) onto disk
      # and copies the result to any configured `publish_to` / `publish_each`
      # targets. Fires `:built` and `:published` events on the bus, tagged with
      # the request's correlation_id for traceability.
      class Build
        def initialize(ctx:, bus:)
          @ctx = ctx
          @bus = bus
        end

        def call(prefix: nil)
          built = []
          manifest.entries.each do |mentry|
            next unless mentry.in_generator_zone?
            next unless mentry.projection || mentry.template
            next if prefix && !mentry.key.start_with?(prefix)

            built << materialize(mentry)
          end
          published_leaves = publish_leaves(prefix: prefix)
          { "protocol" => Textus::PROTOCOL, "built" => built, "published_leaves" => published_leaves }
        end

        private

        def store = @ctx.store
        def manifest = store.manifest
        def root = store.root

        def publish_leaves(prefix: nil)
          repo_root = File.dirname(root)
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
          out
        end

        def publish_leaf(mentry, row, repo_root)
          target_rel = mentry.publish_target_for(row[:key])
          target_abs = File.expand_path(File.join(repo_root, target_rel))
          unless target_abs.start_with?(File.expand_path(repo_root) + File::SEPARATOR)
            raise PublishError.new(
              "entry '#{mentry.key}': publish_each target '#{target_rel}' for key '#{row[:key]}' escapes repo root",
            )
          end

          Textus::Infra::Publisher.publish(source: row[:path], target: target_abs, store_root: root)
          publish_event(:published,
                        key: row[:key],
                        envelope: store.get(row[:key]),
                        source: row[:path],
                        target: target_abs)
          { "key" => row[:key], "source" => row[:path], "target" => target_abs }
        end

        def materialize(mentry)
          target_path = Builder::Pipeline.run(
            store: store,
            mentry: mentry,
            template_loader: ->(name) { read_template(name) },
          )
          publish_and_fire(mentry, target_path)
          { "key" => mentry.key, "path" => target_path, "published_to" => mentry.publish_to }
        end

        def read_template(name)
          tpl_path = File.join(root, "templates", name)
          raise TemplateError.new("template not found: #{tpl_path}", template_name: name) unless File.exist?(tpl_path)

          File.read(tpl_path)
        end

        def publish_and_fire(mentry, target_path)
          envelope = store.get(mentry.key)
          repo_root = File.dirname(root)

          mentry.publish_to.each do |rel|
            target_abs = File.join(repo_root, rel)
            Textus::Infra::Publisher.publish(source: target_path, target: target_abs, store_root: root)
            publish_event(:published,
                          key: mentry.key,
                          envelope: envelope,
                          source: target_path,
                          target: target_abs)
          end

          publish_event(:built,
                        key: mentry.key,
                        envelope: envelope,
                        sources: Array(mentry.projection&.fetch("select", nil)).compact)
        end

        def publish_event(event, **payload)
          # `with_role` returns a Context that preserves the original
          # correlation_id, so hooks reading `store.correlation_id` see the
          # same value as the event's top-level correlation_id key.
          @bus.publish(event, store: @ctx.with_role(@ctx.role), correlation_id: @ctx.correlation_id, **payload)
        end
      end
    end
  end
end
