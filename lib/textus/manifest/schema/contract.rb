# frozen_string_literal: true

require "dry/schema"

module Textus
  class Manifest
    module Schema
      # rubocop:disable Metrics/BlockLength
      Contract = Dry::Schema.JSON do
        config.validate_keys = true

        required(:lanes).value(:array).each do
          hash do
            required(:name).value(:string)
            required(:kind).value(included_in?: Vocabulary::LANE_KINDS)
            optional(:owner).value(:string)
            optional(:desc).value(:string)
          end
        end

        optional(:roles).value(:array).each do
          hash do
            required(:name).value(:string)
            optional(:can).value(:array).each(:string)
          end
        end

        required(:entries).value(:array).each do
          hash do
            required(:key).value(:string)
            required(:lane).value(:string)
            optional(:path).value(:string)
            optional(:owner).value(:string)
            optional(:format).value(:string)
            optional(:schema).value(:string)
            optional(:kind).value(:string)
            optional(:nested).value(:bool)
            optional(:tracked).value(:bool)
            optional(:ignore).value(:bool)
            optional(:source).hash do
              optional(:from).value(:string)
              optional(:command).value(:string)
              optional(:sources).value(:array)
            end
            optional(:publish).value(:array).each do
              hash do
                optional(:to).value(:string)
                optional(:tree).value(:string)
                optional(:template).value(:string)
                optional(:inject_boot).value(:bool)
              end
            end
          end
        end

        optional(:rules).value(:array).each do
          hash do
            optional(:match).value(:string)
            optional(:guard)
            optional(:retention).hash do
              optional(:ttl).value(:string)
              optional(:action).value(:string)
            end
            optional(:react)
          end
        end

        optional(:audit).hash do
          optional(:max_size).value(:integer)
          optional(:keep).value(:integer)
        end
        optional(:version).value(:string)
      end
      # rubocop:enable Metrics/BlockLength
    end
  end
end
