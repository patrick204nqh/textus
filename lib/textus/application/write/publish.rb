module Textus
  module Application
    module Write
      # Single-pass publish use case: dispatches polymorphically to each
      # entry's `publish_via` method. Derived entries materialize their body
      # via Materializer; Nested entries fan out via publish_each; Leaf and
      # Intake entries copy their stored body to publish_to targets. The
      # Publish layer owns wiring (context, accumulation) but not per-kind
      # logic.
      #
      # Return shape: { "protocol", "built", "published_leaves" }
      class Publish
        def initialize(container:, call:, hook_context:, session:)
          @container    = container
          @call         = call
          @manifest     = container.manifest
          @file_store   = container.file_store
          @events       = container.events
          @root         = container.root
          @rpc          = container.rpc
          @session      = session
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
            caps: caps_struct,
            rpc: @rpc,
            session: @session,
            ctx: @call,
            bus: @events,
            hook_context: @hook_context,
            reader: reader,
            emit: ->(event, **payload) { @events.publish(event, ctx: @hook_context, **payload) },
          )
        end

        # Reconstruct a write-caps-shaped struct for downstream consumers
        # (Materializer) that still take caps:. Mirrors WriteCaps fields.
        def caps_struct
          @caps_struct ||= Struct.new(
            :manifest, :file_store, :schemas, :root, :audit_log, :events, :authorizer
          ).new(
            @manifest, @file_store, @container.schemas, @root,
            @container.audit_log, @events, @container.authorizer
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
          @reader ||= Textus::Application::Read::Get.new(container: @container, call: @call)
        end
      end
    end
  end
end

Textus::Application::UseCase.register(:publish, Textus::Application::Write::Publish, caps: :write)
