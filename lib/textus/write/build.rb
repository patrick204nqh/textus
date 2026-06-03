module Textus
  module Write
    # Single-pass build use case (the verb `build`, ADR 0061): dispatches
    # polymorphically to each entry's `publish_via` method — the copy-out step
    # (`publish` is the output-destination concept the verb drives, not the verb).
    # Derived entries materialize their body via Materializer; Nested entries
    # mirror their subtree via publish_tree; Leaf and Intake entries copy their
    # stored body to publish_to targets. The Build layer owns wiring (context,
    # accumulation) but not per-kind logic.
    #
    # Return shape: { "protocol", "built", "published_leaves" }
    class Build
      extend Textus::Contract::DSL

      verb     :build
      summary  "materialize derived entries; publish_to and publish_tree fan out copies"
      surfaces :cli, :mcp
      cli      "build"
      around   :build_lock
      arg :prefix, String, required: false, description: "limit the build to keys under this prefix"

      def initialize(container:, call:)
        @container = container
        @call      = call
        @manifest  = container.manifest
      end

      def call(prefix: nil)
        build_role = @manifest.policy.actor_for("build") or
          raise Textus::UsageError.new(
            "no role holds the 'build' capability",
            hint: "declare a role with `can: [build]` in .textus/manifest.yaml",
          )
        build_call = Textus::Call.build(
          role: build_role,
          correlation_id: @call.correlation_id,
          dry_run: @call.dry_run,
        )

        built  = []
        leaves = []
        pruned = []
        context = build_context(build_call)

        @manifest.data.entries.each do |mentry|
          next if prefix && !entry_matches_prefix?(mentry, prefix)

          result = mentry.publish_via(context, prefix: prefix)
          next if result.nil?

          case result[:kind]
          when :built then built << result[:value]
          when :leaves
            leaves.concat(result[:value])
            pruned.concat(result[:pruned]) if result[:pruned]
          end
        end

        { "protocol" => Textus::PROTOCOL, "built" => built, "published_leaves" => leaves, "pruned" => pruned }
      end

      private

      def build_context(call)
        Textus::Manifest::Entry::Base::PublishContext.new(
          container: @container,
          call: call,
          reader: reader(call),
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

      def reader(call)
        Textus::Read::Get.new(container: @container, call: call)
      end
    end
  end
end
