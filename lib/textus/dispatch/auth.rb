# frozen_string_literal: true

module Textus
  module Dispatch
    class Auth
      FLOOR = {
        put: %w[lane_writable_by],
        key_delete: %w[lane_writable_by],
        key_mv: %w[lane_writable_by],
        accept: %w[author_held target_is_canon],
        reject: %w[author_held],
        converge: %w[lane_writable_by],
      }.freeze

      AuthContext = Struct.new(
        :actor, :actor_caps, :lane_verb,
        :action, :target, :envelope,
        :mentry, :manifest,
        keyword_init: true
      )

      def initialize(manifest:, schemas:)
        @manifest = manifest
        @schemas = schemas
      end

      def check!(action:, actor:, key:, envelope: nil, extra: {})
        mentry = @manifest.resolver.resolve(key).entry
        lane_verb = @manifest.policy.verb_for_lane(mentry.lane.to_s)
        actor_caps = Set.new(@manifest.data.role_caps.fetch(actor, []))

        floor_preds = FLOOR.fetch(action.to_sym, [])
        rule_preds = rule_declared_predicates(action, key)

        ctx = AuthContext.new(
          actor: actor,
          actor_caps: actor_caps,
          lane_verb: lane_verb,
          action: action,
          target: key,
          envelope: envelope,
          mentry: mentry,
          manifest: @manifest,
        )

        failures = []
        (floor_preds + rule_preds).uniq.each do |pred_name|
          result = evaluate(pred_name, ctx, extra)
          next if result[:pass]
          raise result[:error] if result[:error]

          failures << [pred_name, result[:reason]]
        end

        raise Textus::GuardFailed.new(failures) unless failures.empty?
      rescue Textus::UnknownKey
        if action.to_sym == :accept
          raise Textus::GuardFailed.new([["target_is_canon", "proposal target '#{key}' resolves to no declared entry"]])
        end

        raise
      end

      def check_event!(event)
        return if event.actor.to_s == Textus::Role::AUTOMATION
        return if event.target.to_s.empty?

        action_sym = event.name.to_s.split(".").last.to_sym
        check!(action: action_sym, actor: event.actor, key: event.target)
      rescue Textus::UnknownKey
        nil
      end

      private

      def rule_declared_predicates(action, key)
        guard_map = @manifest.rules.for(key).guard
        return [] if guard_map.nil?

        Array(guard_map[action.to_s])
      end

      def evaluate(pred_name, ctx, extra)
        case pred_name
        when "lane_writable_by"
          evaluate_lane_writable_by(ctx)
        when "author_held"
          evaluate_author_held(ctx)
        when "target_is_canon"
          evaluate_target_is_canon(ctx)
        when "etag_match"
          evaluate_etag_match(ctx, extra)
        when "schema_valid"
          evaluate_schema_valid(ctx)
        when "fresh_within"
          evaluate_fresh_within(ctx)
        else
          raise Textus::UsageError.new("unknown predicate '#{pred_name}'")
        end
      end

      def evaluate_lane_writable_by(ctx)
        pass = ctx.actor_caps.include?(ctx.lane_verb.to_s)
        return { pass: true } if pass

        holders = @manifest.policy.roles_with_capability(ctx.lane_verb.to_s)
        {
          pass: false,
          error: Textus::WriteForbidden.new(
            ctx.mentry.key,
            ctx.mentry.lane,
            verb: ctx.lane_verb,
            holders: holders,
          ),
        }
      end

      def evaluate_author_held(ctx)
        holders = @manifest.policy.roles_with_capability("author")
        pass = holders.include?(ctx.actor.to_s)
        reason =
          if pass
            nil
          elsif holders.empty?
            "no role holds the 'author' capability; #{ctx.action} is disabled"
          else
            "role '#{ctx.actor}' lacks the 'author' capability (held by: #{holders.join(", ")})"
          end
        { pass: pass, reason: reason }
      end

      def evaluate_target_is_canon(ctx)
        kind = @manifest.policy.declared_kind(ctx.mentry.lane.to_s)
        pass = kind == :canon
        reason = "target lane '#{ctx.mentry.lane}' is not canon (kind: #{kind})"
        { pass: pass, reason: pass ? nil : reason }
      end

      def evaluate_etag_match(ctx, extra)
        if_etag = extra[:if_etag]
        return { pass: true } if if_etag.nil?

        current = ctx.envelope&.etag
        pass = current.nil? || current == if_etag
        {
          pass: pass,
          error: pass ? nil : Textus::EtagMismatch.new(ctx.target, if_etag, current),
        }
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

      def evaluate_fresh_within(_ctx)
        { pass: true }
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
