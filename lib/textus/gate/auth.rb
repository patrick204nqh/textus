# frozen_string_literal: true

module Textus
  class Gate
    class Auth
      FLOOR = {
        put: %w[lane_writable_by raw_lane_ingest_only],
        key_delete: %w[lane_deletable_by],
        key_mv: %w[lane_writable_by raw_lane_ingest_only],
        accept: %w[author_held],
        reject: %w[author_held],
        propose: %w[lane_writable_by raw_lane_ingest_only],
        key_mv_prefix: %w[lane_writable_by raw_lane_ingest_only],
        key_delete_prefix: %w[lane_writable_by raw_lane_ingest_only],
        ingest: %w[lane_writable_by raw_write_once],
      }.freeze

      AuthContext = Struct.new(
        :actor, :actor_caps, :lane_verb,
        :action, :target, :envelope,
        :mentry, :manifest,
        keyword_init: true
      )

      def initialize(container)
        @manifest = container.manifest
        @schemas = container.schemas
      end

      def check!(cmd)
        key = extract_key(cmd)
        return unless key

        evaluate_predicates(
          action: cmd.verb,
          actor: cmd.role.to_s,
          key: key,
          envelope: nil,
          extra: {},
        )
      end

      # Backward-compatible check for inline action auth (accept, put, etc.).
      def check_action!(action:, actor:, key:, envelope: nil, extra: {})
        evaluate_predicates(
          action: action.to_sym,
          actor: actor,
          key: key,
          envelope: envelope,
          extra: extra,
        )
      end

      private

      def evaluate_predicates(action:, actor:, key:, envelope:, extra:)
        mentry = @manifest.resolver.resolve(key).entry
        lane_verb = @manifest.policy.verb_for_lane(mentry.lane.to_s)
        actor_caps = Set.new(@manifest.data.role_caps.fetch(actor, []))

        ctx = AuthContext.new(
          actor:, actor_caps:, lane_verb:,
          action:, target: key, envelope:,
          mentry:, manifest: @manifest
        )

        failures = []
        floor_preds = FLOOR.fetch(action, [])
        rule_preds = rule_declared_predicates(action, key)
        (floor_preds + rule_preds).uniq.each do |pred|
          result = evaluate(pred, ctx, extra)
          next if result[:pass]
          raise result[:error] if result[:error]

          failures << [pred, result[:reason]]
        end
        raise Textus::GuardFailed.new(failures) unless failures.empty?
      end

      def extract_key(cmd)
        cmd.params.key?(:pending_key) ? cmd.pending_key : cmd.key
      end

      def rule_declared_predicates(action, key)
        guard_map = @manifest.rules.for(key).guard
        return [] if guard_map.nil?

        Array(guard_map[action.to_s])
      end

      def evaluate(pred_name, ctx, extra)
        case pred_name
        when "lane_writable_by"      then evaluate_lane_writable_by(ctx)
        when "author_held"           then evaluate_author_held(ctx)
        when "target_is_canon"       then evaluate_target_is_canon(ctx)
        when "etag_match"            then evaluate_etag_match(ctx, extra)
        when "schema_valid"          then evaluate_schema_valid(ctx)
        when "fresh_within"          then { pass: true }
        when "raw_lane_ingest_only"  then evaluate_raw_lane_ingest_only(ctx)
        when "raw_write_once"        then evaluate_raw_write_once(ctx)
        when "lane_deletable_by"     then evaluate_lane_deletable_by(ctx)
        else raise Textus::UsageError.new("unknown predicate '#{pred_name}'")
        end
      end

      def evaluate_lane_writable_by(ctx)
        pass = ctx.actor_caps.include?(ctx.lane_verb.to_s)
        return { pass: true } if pass

        holders = @manifest.policy.roles_with_capability(ctx.lane_verb.to_s)
        { pass: false, error: Textus::WriteForbidden.new(ctx.mentry.key, ctx.mentry.lane, verb: ctx.lane_verb, holders:) }
      end

      def evaluate_author_held(ctx)
        holders = @manifest.policy.roles_with_capability("author")
        pass = holders.include?(ctx.actor.to_s)
        reason = if pass
                   nil
                 elsif holders.empty?
                   "no role holds the 'author' capability; #{ctx.action} is disabled"
                 else
                   "role '#{ctx.actor}' lacks the 'author' capability (held by: #{holders.join(", ")})"
                 end
        { pass:, reason: }
      end

      def evaluate_target_is_canon(ctx)
        kind = @manifest.policy.declared_kind(ctx.mentry.lane.to_s)
        pass = kind == :canon
        { pass:, reason: pass ? nil : "target lane '#{ctx.mentry.lane}' is not canon (kind: #{kind})" }
      end

      def evaluate_etag_match(ctx, extra)
        if_etag = extra[:if_etag]
        return { pass: true } if if_etag.nil?

        current = ctx.envelope&.etag
        pass = current.nil? || current == if_etag
        { pass:, error: pass ? nil : Textus::EtagMismatch.new(ctx.target, if_etag, current) }
      end

      def evaluate_schema_valid(ctx)
        return { pass: true } unless ctx.envelope

        schema_ref = ctx.mentry.schema
        return { pass: true } unless schema_ref

        schema = @schemas.fetch_or_nil(schema_ref)
        return { pass: true } unless schema

        frontmatter = ctx.envelope.meta&.dig("_meta") || ctx.envelope.meta || {}
        begin
          schema.validate!(frontmatter)
          { pass: true }
        rescue Textus::SchemaViolation => e
          { pass: false, reason: schema_reason(e) }
        end
      end

      def evaluate_raw_lane_ingest_only(ctx)
        return { pass: true } unless @manifest.policy.declared_kind(ctx.mentry.lane.to_s) == :raw
        return { pass: true } if ctx.action == :ingest

        { pass: false, error: Textus::Error.new(
          :raw_lane_ingest_only,
          "raw lane '#{ctx.mentry.lane}' only accepts `textus ingest` — " \
          "use that verb instead of '#{ctx.action}'",
        ) }
      end

      def evaluate_raw_write_once(ctx)
        path = @manifest.resolver.resolve(ctx.target).path
        return { pass: true } unless File.exist?(path)

        { pass: false, error: Textus::Error.new(
          :raw_write_once,
          "raw entry '#{ctx.target}' already exists; " \
          "delete it first (`textus key-delete #{ctx.target}`), then re-ingest",
        ) }
      end

      # Deletion authority: the lane's write capability OR the author capability.
      # On raw-kind lanes only the author capability grants deletion (correction
      # escape hatch); the lane's own verb (ingest) is write-only. On all other
      # lane kinds the behaviour matches lane_writable_by — the lane's writer
      # can delete as before.
      def evaluate_lane_deletable_by(ctx)
        is_raw = @manifest.policy.declared_kind(ctx.mentry.lane.to_s) == :raw
        pass = if is_raw
                 ctx.actor_caps.include?("author")
               else
                 ctx.actor_caps.include?(ctx.lane_verb.to_s) || ctx.actor_caps.include?("author")
               end
        return { pass: true } if pass

        extra_holders = is_raw ? ["author"] : [ctx.lane_verb.to_s, "author"]
        holders = extra_holders.flat_map { |v| @manifest.policy.roles_with_capability(v) }.uniq
        { pass: false, error: Textus::WriteForbidden.new(ctx.mentry.key, ctx.mentry.lane,
                                                         verb: ctx.lane_verb, holders:) }
      end

      def schema_reason(err)
        d = err.details
        return err.message.dup unless d.is_a?(Hash)
        return "missing required fields: #{Array(d["missing"]).join(", ")}" if d["missing"]
        return "field '#{d["field"]}': #{d["reason"]}" if d["field"]

        err.message.dup
      end
    end
  end
end
