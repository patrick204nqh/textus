# frozen_string_literal: true

module Textus
  module Action
    class RuleExplain < Base
      extend Textus::Contract::DSL

      verb :rule_explain
      summary "Effective rules for a key. Lean {lifecycle, guard} by default; detail: true adds matched blocks + guard predicates."
      surfaces :cli, :mcp
      cli "rule explain"
      arg :key, String, required: true, positional: true,
                        description: "dotted key whose effective rules you want (lifecycle ttl/action, write guard, ...)"
      arg :detail, :boolean,
          description: "defaults false: lean {lifecycle, guard}. detail: true adds matched blocks + guard predicates per transition."
      view(:cli) { |r| { "verb" => "rule_explain" }.merge(r.transform_keys(&:to_s)) }

      BURN = :sync

      def initialize(key:, detail: nil)
        super()
        @key = key
        @detail = detail
      end

      def call(container:, **)
        @manifest = container.manifest
        @detail ? explain(@key) : effective(@key)
      end

      REGISTRY = Textus::Manifest::Schema::FIELD_REGISTRY
      LEAN_FIELDS = REGISTRY.select { |_, m| m[:in_rule_explain].include?(:lean) }.keys.freeze
      DETAIL_FIELDS = REGISTRY.select { |_, m| m[:in_rule_explain].include?(:detail) }.keys.freeze
      EFFECTIVE_FIELDS = DETAIL_FIELDS.select { |f| REGISTRY[f][:policy_class] }.freeze

      private

      def effective(key)
        set = @manifest.rules.for(key)
        LEAN_FIELDS.each_with_object({}) do |field, out|
          value = set.public_send(field)
          out[field.to_s] = lean_value(field, value) unless value.nil?
        end
      end

      def lean_value(field, value)
        case field
        when :retention
          retention_hash(value, string_keys: true)
        when :react
          value.to_h
        else
          value
        end
      end

      def explain(key)
        matching = @manifest.rules.explain(key)
        winners = @manifest.rules.for(key)
        {
          key: key,
          matched_blocks: matching.map do |block|
            { match: block.match }.merge(DETAIL_FIELDS.to_h { |f| [f, !block.public_send(f).nil?] })
          end,
          effective: EFFECTIVE_FIELDS.to_h { |f| [f, effective_value(f, winners.public_send(f))] },
          guards: Textus::Gate::Auth::FLOOR.keys.to_h do |action|
            floor = Textus::Gate::Auth::FLOOR.fetch(action, [])
            rule = Array(@manifest.rules.for(key).guard&.dig(action.to_s))
            [action, { floor: floor, rule: rule }]
          end,
        }
      end

      def effective_value(field, value)
        return nil if value.nil?

        case field
        when :retention
          retention_hash(value, string_keys: false)
        when :react
          value.to_h
        when :handler_permit
          value.handlers
        else
          value
        end
      end

      def retention_hash(retention, string_keys:)
        h = { ttl_seconds: retention.ttl_seconds, action: retention.action }
        string_keys ? h.transform_keys(&:to_s) : h
      end
    end
  end
end
