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
      module Publish
        def self.call(*, session:, ctx:, caps:, **)
          Impl.new(
            ctx: ctx, caps: caps,
            rpc: session.rpc,
            boot: session.method(:boot),
            hook_context: session.hook_context
          ).call(*, **)
        end

        class Impl
          def initialize(ctx:, caps:, rpc:, boot:, hook_context:)
            @ctx          = ctx
            @caps         = caps
            @manifest     = caps.manifest
            @file_store   = caps.file_store
            @events       = caps.events
            @root         = caps.root
            @rpc          = rpc
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
              caps: @caps,
              rpc: @rpc,
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
            @reader ||= Textus::Application::Reads::Get::Impl.new(ctx: @ctx, caps: @caps)
          end
        end
      end
    end
  end
end

Textus::Application::UseCase.register(:publish, Textus::Application::Writes::Publish, caps: :write)
