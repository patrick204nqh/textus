# frozen_string_literal: true

require "dry/schema"

module Textus
  class Manifest
    module Schema
      # rubocop:disable Metrics/BlockLength
      Contract = Dry::Schema.JSON do
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

        optional(:entries).value(:array).each do
          hash do
            required(:key).value(:string)
            required(:lane).value(:string)
            optional(:path).value(:string)
            optional(:owner).value(:string)
            optional(:format).value(:string)
            optional(:schema).maybe(:string)
            optional(:kind).value(:string)
            optional(:nested).value(:bool)
            optional(:tracked).value(:bool)
            optional(:ignore)
            optional(:source)
            optional(:publish).value(:array)
          end
        end

        optional(:rules).value(:array).each do
          hash do
            optional(:match).value(:string)
            optional(:guard)
            optional(:retention)
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
