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
        def initialize(container:, call:, hook_context: nil)
          @container    = container
          @call         = call
          @manifest     = container.manifest
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
            container: @container,
            call: @call,
            reader: reader,
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
