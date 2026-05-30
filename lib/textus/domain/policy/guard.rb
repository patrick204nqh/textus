# frozen_string_literal: true

module Textus
  module Domain
    module Policy
      # An ordered list of pure predicates over one Evaluation (ADR 0031).
      # check! short-circuits on the first failing predicate that defines a
      # bespoke #error (only zone_writable_by → WriteForbidden, the product's
      # legible topology refusal); every other failure accumulates into
      # GuardFailed naming the unmet predicate(s).
      class Guard
        attr_reader :predicates

        def initialize(predicates)
          @predicates = predicates
        end

        def check!(eval)
          accumulated = []
          @predicates.each do |pred|
            next if pred.call(eval)
            raise pred.error(eval) if pred.respond_to?(:error)

            accumulated << [pred.name, pred.reason]
          end
          raise Textus::GuardFailed.new(accumulated) unless accumulated.empty?
        end

        def explain(eval)
          @predicates.map { |p| [p.name, p.call(eval), p.reason] }
        end
      end
    end
  end
end
