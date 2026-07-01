# frozen_string_literal: true

module Textus
  module UseCases
    module Ops
      module RuleList
        HANDLES = Dispatch::Contracts::RuleList
        NEEDS = %i[manifest].freeze

        LIST_FIELDS = Textus::Manifest::Schema::FIELD_REGISTRY.select { |_, m| m[:in_rule_list] }.keys.freeze

        def self.call(_command, _call, deps)
          Value::Result.success(deps.manifest.rules.blocks.map do |block|
            row = { "match" => block.match }
            LIST_FIELDS.each do |field|
              value = block.public_send(field)
              row[field.to_s] = serialize(field, value) unless value.nil?
            end
            row
          end)
        end

        def self.serialize(field, value)
          case field
          when :retention then { "ttl_seconds" => value.ttl_seconds, "action" => value.action.to_s }
          when :react then value.to_h
          else value
          end
        end
      end
    end
  end
end
