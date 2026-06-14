# frozen_string_literal: true

module Textus
  class Gate
    class Auth
      FLOOR = {
        put: %w[lane_writable_by],
        key_delete: %w[lane_writable_by],
        key_mv: %w[lane_writable_by],
        accept: %w[author_held target_is_canon],
        reject: %w[author_held],
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

      # Command-based check (new Gate path).
      def check!(cmd) # rubocop:disable Metrics/AbcSize
        return if cmd.role.to_s == Textus::Role::AUTOMATION

        key = cmd.respond_to?(:key) ? cmd.key : nil
        return unless key

        action_sym = command_to_action(cmd)
        mentry = @manifest.resolver.resolve(key).entry
        lane_verb = @manifest.policy.verb_for_lane(mentry.lane.to_s)
        actor_caps = Set.new(@manifest.data.role_caps.fetch(cmd.role.to_s, []))

        ctx = AuthContext.new(
          actor: cmd.role, actor_caps:, lane_verb:,
          action: action_sym, target: key, envelope: nil,
          mentry:, manifest: @manifest
        )

        failures = []
        floor_preds = FLOOR.fetch(action_sym, [])
        rule_preds = rule_declared_predicates(action_sym, key)
        (floor_preds + rule_preds).uniq.each do |pred|
          result = evaluate(pred, ctx, {})
          next if result[:pass]
          raise result[:error] if result[:error]

          failures << [pred, result[:reason]]
        end
        raise Textus::GuardFailed.new(failures) unless failures.empty?
      rescue Textus::UnknownKey
        raise if cmd.is_a?(Textus::Command::Accept)

        raise
      end

      # Backward-compatible check for inline action auth (accept, put, etc.).
      def check_action!(action:, actor:, key:, envelope: nil, extra: {})
        mentry = @manifest.resolver.resolve(key).entry
        lane_verb = @manifest.policy.verb_for_lane(mentry.lane.to_s)
        actor_caps = Set.new(@manifest.data.role_caps.fetch(actor, []))

        ctx = AuthContext.new(
          actor:, actor_caps:, lane_verb:,
          action: action.to_sym, target: key, envelope:,
          mentry:, manifest: @manifest
        )

        failures = []
        floor_preds = FLOOR.fetch(action.to_sym, [])
        rule_preds = rule_declared_predicates(action, key)
        (floor_preds + rule_preds).uniq.each do |pred|
          result = evaluate(pred, ctx, extra)
          next if result[:pass]
          raise result[:error] if result[:error]

          failures << [pred, result[:reason]]
        end
        raise Textus::GuardFailed.new(failures) unless failures.empty?
      rescue Textus::UnknownKey
        raise if action.to_s == "accept"

        raise
      end

      private

      def command_to_action(cmd)
        cmd.class.name.split("::").last
           .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
           .gsub(/([a-z\d])([A-Z])/, '\1_\2')
           .downcase.to_sym
      end

      def rule_declared_predicates(action, key)
        guard_map = @manifest.rules.for(key).guard
        return [] if guard_map.nil?

        Array(guard_map[action.to_s])
      end

      def evaluate(pred_name, ctx, extra)
        case pred_name
        when "lane_writable_by"  then evaluate_lane_writable_by(ctx)
        when "author_held"       then evaluate_author_held(ctx)
        when "target_is_canon"   then evaluate_target_is_canon(ctx)
        when "etag_match"        then evaluate_etag_match(ctx, extra)
        when "schema_valid"      then evaluate_schema_valid(ctx)
        when "fresh_within"      then { pass: true }
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
        reason = pass ? nil : "role '#{ctx.actor}' lacks the 'author' capability (held by: #{holders.join(", ")})"
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
