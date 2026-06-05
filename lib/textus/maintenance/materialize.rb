module Textus
  module Maintenance
    # Internal single-pass materialize service (formerly the `build` verb,
    # ADR 0061; demoted to a contract-less service by ADR 0087). Dispatches
    # polymorphically to each entry's `publish_via`. Callers: Reconcile (full,
    # Phase 1) and ReactiveMaterialize (scoped to an rdeps impact set). The
    # materialize-actor resolution lives here; locking is the caller's
    # responsibility (the reconcile / reactive path wraps it via the
    # maintenance lock).
    class Materialize
      def initialize(container:, call:)
        @container = container
        @call      = call
        @manifest  = container.manifest
      end

      # prefix: limit to a dotted prefix. keys: limit to an explicit set of
      # entry keys (the rdeps impact set). When both nil, materialize everything.
      def call(prefix: nil, keys: nil)
        build_call = build_actor_call
        built = []
        leaves = []
        pruned = []
        context = build_context(build_call)

        @manifest.data.entries.each do |mentry|
          next if prefix && !entry_matches_prefix?(mentry, prefix)
          next if keys && !keys.include?(mentry.key)

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

      def build_actor_call
        build_role = @manifest.policy.actor_for("reconcile") or
          raise Textus::UsageError.new(
            "no role holds the 'reconcile' capability",
            hint: "declare a role with `can: [reconcile]` in .textus/manifest.yaml",
          )
        Textus::Call.build(
          role: build_role,
          correlation_id: @call.correlation_id,
          dry_run: @call.dry_run,
        )
      end

      def build_context(call)
        Textus::Manifest::Entry::Base::PublishContext.new(
          container: @container, call: call, reader: Textus::Read::Get.new(container: @container, call: call),
        )
      end

      def entry_matches_prefix?(mentry, prefix)
        case mentry
        when Textus::Manifest::Entry::Nested
          mentry.key.start_with?(prefix) || prefix.start_with?("#{mentry.key}.")
        else
          mentry.key.start_with?(prefix)
        end
      end
    end
  end
end
