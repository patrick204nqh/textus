module Textus
  module Handlers
    class RuleExplain
      def initialize(manifest:)
        @manifest = manifest
      end

      def call(command, _call)
        key = command.key
        result = if command.detail
                   explain(key)
                 else
                   effective(key)
                 end
        Result.success(result)
      end

      LEAN_FIELDS = Textus::Manifest::Schema::FIELD_REGISTRY
                    .select { |_, m| m[:in_rule_explain].include?(:lean) }.keys.freeze
      DETAIL_FIELDS = Textus::Manifest::Schema::FIELD_REGISTRY
                      .select { |_, m| m[:in_rule_explain].include?(:detail) }.keys.freeze
      EFFECTIVE_FIELDS = DETAIL_FIELDS.select { |f| Textus::Manifest::Schema::FIELD_REGISTRY[f][:policy_class] }.freeze

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
        when :retention then retention_hash(value, string_keys: true)
        when :react then value.to_h
        else value
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
          guards: Textus::Manifest::Policy::Predicates::FLOOR.keys.to_h do |action|
            floor = Textus::Manifest::Policy::Predicates::FLOOR.fetch(action, [])
            rule = Array(@manifest.rules.for(key).guard&.dig(action.to_s))
            [action, { floor: floor, rule: rule }]
          end,
        }
      end

      def effective_value(field, value)
        return nil if value.nil?

        case field
        when :retention then retention_hash(value, string_keys: false)
        when :react then value.to_h
        else value
        end
      end

      def retention_hash(retention, string_keys:)
        h = { ttl_seconds: retention.ttl_seconds, action: retention.action }
        string_keys ? h.transform_keys(&:to_s) : h
      end
    end
  end
end
