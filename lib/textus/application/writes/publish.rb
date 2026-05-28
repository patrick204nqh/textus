module Textus
  module Application
    module Writes
      # Single-pass publish use case: dispatches polymorphically to each
      # entry's `publish_via` method. Derived entries materialize their body
      # via Materializer; Nested entries fan out via publish_each; Leaf and
      # Intake entries copy their stored body to publish_to targets. The
      # Publish layer owns wiring (context, accumulation) but not per-kind
      # logic.
      #
      # Return shape: { "protocol", "built", "published_leaves" }
      class Publish
        def initialize(ctx:, ports:, boot:, hook_context:)
          @ctx          = ctx
          @ports        = ports
          @manifest     = ports.manifest
          @file_store   = ports.file_store
          @events       = ports.event_bus
          @root         = ports.root
          @boot         = boot
          @hook_context = hook_context
        end

        def call(prefix: nil)
          built  = []
          leaves = []
          context = build_context

          @manifest.data.entries.each do |mentry|
            next if prefix && !entry_matches_prefix?(mentry, prefix)

            result = mentry.publish_via(context, prefix: prefix)
            next if result.nil?

            case result[:kind]
            when :built  then built << result[:value]
            when :leaves then leaves.concat(result[:value])
            end
          end

          { "protocol" => Textus::PROTOCOL, "built" => built, "published_leaves" => leaves }
        end

        private

        def build_context
          Textus::Manifest::Entry::Base::PublishContext.new(
            repo_root: File.dirname(@root),
            manifest: @manifest,
            file_store: @file_store,
            root: @root,
            ports: @ports,
            boot: @boot,
            ctx: @ctx,
            bus: @events,
            hook_context: @hook_context,
            reader: reader,
            emit: ->(event, **payload) { @events.publish(event, ctx: @hook_context, **payload) },
          )
        end

        # Whether the entry should be processed for the given prefix filter.
        def entry_matches_prefix?(mentry, prefix)
          return true unless prefix

          case mentry
          when Textus::Manifest::Entry::Nested
            mentry.key.start_with?(prefix) ||
              prefix.start_with?("#{mentry.key}.")
          else
            mentry.key.start_with?(prefix)
          end
        end

        def reader
          @reader ||= Textus::Application::Reads::Get.new(ctx: @ctx, ports: @ports)
        end
      end
    end
  end
end
