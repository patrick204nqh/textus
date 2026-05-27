module Textus
  module Application
    module Writes
      # Single-pass publish use case: materializes Derived entries (template +
      # projection + external runner) AND copies Leaf/Nested entries to their
      # publish targets. Replaces the former two-step Build + Publish split.
      #
      # Return shape: { "protocol", "built", "published_leaves" }
      # — wire-compatible with what the `textus build` CLI verb previously
      #   assembled by merging Build + old Publish results.
      class Publish
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
          built  = []
          leaves = []
          repo_root = File.dirname(@root)

          @manifest.entries.each do |mentry|
            next if prefix && !entry_matches_prefix?(mentry, prefix)

            case mentry
            when Textus::Manifest::Entry::Derived
              next unless mentry.in_generator_zone?

              result = materialize_derived(mentry, repo_root)
              built << result if result
            when Textus::Manifest::Entry::Nested
              next unless mentry.publish_each

              publish_nested(mentry, repo_root, prefix, leaves)
            when Textus::Manifest::Entry::Leaf
              next if Array(mentry.publish_to).empty?

              result = publish_leaf_entry(mentry, repo_root)
              built << result if result
            end
          end

          { "protocol" => Textus::PROTOCOL, "built" => built, "published_leaves" => leaves }
        end

        private

        # Materialize a Derived entry and copy to publish_to targets.
        def materialize_derived(mentry, repo_root)
          target_path = Materializer.new(
            ctx: @ctx, manifest: @manifest, file_store: @file_store,
            bus: @bus, root: @root, store: @store
          ).run(mentry)

          publish_derived_copies(mentry, target_path, repo_root)
          fire_build_completed(mentry)

          { "key" => mentry.key, "path" => target_path, "published_to" => mentry.publish_to }
        end

        def publish_derived_copies(mentry, target_path, repo_root)
          envelope = reader.call(mentry.key)
          mentry.publish_to.each do |rel|
            target_abs = File.join(repo_root, rel)
            Textus::Infra::Publisher.publish(source: target_path, target: target_abs, store_root: @root)
            publish_event(:file_published,
                          key: mentry.key,
                          envelope: envelope,
                          source: target_path,
                          target: target_abs)
          end
        end

        def fire_build_completed(mentry)
          envelope = reader.call(mentry.key)
          src = mentry.source
          selects = src.is_a?(Textus::Manifest::Entry::Derived::Projection) ? Array(src.select).compact : []
          publish_event(:build_completed,
                        key: mentry.key,
                        envelope: envelope,
                        sources: selects)
        end

        # Publish each leaf under a Nested entry's publish_each pattern.
        def publish_nested(mentry, repo_root, prefix, accumulator)
          @manifest.resolver.enumerate(prefix: mentry.key).each do |row|
            next unless row[:manifest_entry].equal?(mentry)
            next if prefix && !row[:key].start_with?(prefix) && row[:key] != prefix

            accumulator << publish_nested_leaf(mentry, row, repo_root)
          end
        end

        def publish_nested_leaf(mentry, row, repo_root)
          target_rel = mentry.publish_target_for(row[:key])
          target_abs = File.expand_path(File.join(repo_root, target_rel))
          unless target_abs.start_with?(File.expand_path(repo_root) + File::SEPARATOR)
            raise PublishError.new(
              "entry '#{mentry.key}': publish_each target '#{target_rel}' for key '#{row[:key]}' escapes repo root",
            )
          end

          Textus::Infra::Publisher.publish(source: row[:path], target: target_abs, store_root: @root)
          publish_event(:file_published,
                        key: row[:key],
                        envelope: reader.call(row[:key]),
                        source: row[:path],
                        target: target_abs)
          { "key" => row[:key], "source" => row[:path], "target" => target_abs }
        end

        # Publish a standalone Leaf entry that has publish_to targets.
        def publish_leaf_entry(mentry, repo_root)
          source_path = @manifest.resolver.resolve(mentry.key).path
          envelope = reader.call(mentry.key)

          mentry.publish_to.each do |rel|
            target_abs = File.join(repo_root, rel)
            Textus::Infra::Publisher.publish(source: source_path, target: target_abs, store_root: @root)
            publish_event(:file_published,
                          key: mentry.key,
                          envelope: envelope,
                          source: source_path,
                          target: target_abs)
          end

          { "key" => mentry.key, "path" => source_path, "published_to" => mentry.publish_to }
        end

        # Whether the entry should be processed for the given prefix filter.
        def entry_matches_prefix?(mentry, prefix)
          return true unless prefix

          case mentry
          when Textus::Manifest::Entry::Nested
            # Nested: process if the entry key is a prefix of `prefix` or
            # `prefix` is a prefix of the entry key (a leaf under it).
            mentry.key.start_with?(prefix) ||
              prefix.start_with?("#{mentry.key}.")
          else
            mentry.key.start_with?(prefix)
          end
        end

        def reader
          @reader ||= Textus::Application::Reads::Get.new(
            ctx: @ctx, manifest: @manifest, file_store: @file_store,
          )
        end

        def publish_event(event, **payload)
          @bus.publish(event, ctx: @hook_context, **payload)
        end
      end
    end
  end
end
