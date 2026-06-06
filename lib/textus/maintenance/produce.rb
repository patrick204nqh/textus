module Textus
  module Maintenance
    # The single convergence engine (ADR 0093). "Make these machine entries
    # current from upstream." Dispatches per entry kind:
    #   intake  (handler)             -> re-pull (FetchWorker)
    #   derived (template/projection) -> render + publish (publish_via)
    #   derived (command/external)    -> skip (no in-process runner; staleness only)
    # Replaces Maintenance::Materialize and the materialize half of
    # ReactiveMaterialize. Runs as the reconcile build actor (self-elevating);
    # the passed `call` supplies only correlation_id/dry_run. Callers choose the
    # key set: the write subscriber passes rdeps ∩ derived; reconcile passes
    # all-derived + stale-intake.
    class Produce
      def initialize(container:, call:)
        @container = container
        @call      = call
        @manifest  = container.manifest
      end

      # keys: the machine entry keys to converge. Returns
      #   { produced: [k...], skipped: [k...], failed: [{ "key"=>, "error"=> }...] }
      def call(keys:)
        build_call = build_actor_call
        context    = build_context(build_call)
        out = { produced: [], skipped: [], failed: [] }

        keys.each do |key|
          produce_one(key, build_call, context, out)
        rescue Textus::Error => e
          out[:failed] << { "key" => key, "error" => e.message }
        end
        out
      end

      private

      def produce_one(key, build_call, context, out)
        entry = @manifest.resolver.resolve(key).entry
        if entry.intake?
          Write::FetchWorker.new(container: @container, call: build_call).run(key)
          out[:produced] << key
        elsif entry.derived?
          result = entry.publish_via(context)
          result.nil? ? (out[:skipped] << key) : (out[:produced] << key)
        else
          out[:skipped] << key # non-machine entry: nothing to produce
        end
      end

      # --- lifted verbatim from Maintenance::Materialize ---

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
          container: @container, call: call,
          reader: Textus::Read::Get.new(container: @container, call: call)
        )
      end
    end
  end
end
