# frozen_string_literal: true

module Textus
  module Action
    class RuleList < Base
      verb :rule_list
      summary "List every rule block in the manifest."
      surfaces :cli
      cli "rule list"
      view(:cli) { |policies| { "verb" => "rule_list", "policies" => policies } }

      def self.call(container:, call:, **_options) # rubocop:disable Lint/UnusedMethodArgument
        manifest = container.manifest
        Success(manifest.rules.blocks.map do |block|
          row = { "match" => block.match }
          LIST_FIELDS.each do |field|
            value = block.public_send(field)
            row[field.to_s] = serialize(field, value) unless value.nil?
          end
          row
        end)
      end

      LIST_FIELDS = Textus::Manifest::Schema::FIELD_REGISTRY.select { |_, m| m[:in_rule_list] }.keys.freeze

      def self.serialize(field, value)
        case field
        when :retention
          { "ttl_seconds" => value.ttl_seconds, "action" => value.action.to_s }
        when :react
          value.to_h
        else
          value
        end
      end
    end
  end
end
